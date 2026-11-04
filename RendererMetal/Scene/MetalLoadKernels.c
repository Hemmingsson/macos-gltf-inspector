#include "MetalLoadKernels.h"
#include <simd/simd.h>
#include <string.h>

enum { VertexFloats = 20 }; // MetalVertex: position, normal, tangent, colour (float4), uv0, uv1 (float2)

void GLTFMetalExpandRGBA8(const uint8_t *source, size_t sourceBytesPerRow, size_t components, bool keepAlpha,
                          size_t width, size_t height, uint8_t *destination) {
    for (size_t y = 0; y < height; ++y) {
        const uint8_t *src = source + y * sourceBytesPerRow;
        uint8_t *dst = destination + y * width * 4;
        if (components == 4 && keepAlpha) { memcpy(dst, src, width * 4); continue; }
        for (size_t x = 0; x < width; ++x, src += components, dst += 4) {
            dst[0] = src[0]; dst[1] = src[1]; dst[2] = src[2];
            dst[3] = keepAlpha ? src[3] : 255;
        }
    }
}

void GLTFMetalUnpremultiplyRGBA8(uint8_t *pixels, size_t pixelCount) {
    for (size_t i = 0; i < pixelCount; ++i, pixels += 4) {
        const int a = pixels[3];
        if (a > 0 && a < 255) {
            for (int c = 0; c < 3; ++c) {
                const int value = (pixels[c] * 255 + a / 2) / a;
                pixels[c] = (uint8_t)(value < 255 ? value : 255);
            }
        }
    }
}

void GLTFMetalPackVertices(float *vertices, size_t count, const float *positions, const float *normals,
                           const float *tangents, const float *colors, size_t colorComponents,
                           const float *uv0, const float *uv1) {
    for (size_t i = 0; i < count; ++i) {
        float *v = vertices + i * VertexFloats;
        v[0] = positions[i*3]; v[1] = positions[i*3+1]; v[2] = positions[i*3+2]; v[3] = 1;
        if (normals) { v[4] = normals[i*3]; v[5] = normals[i*3+1]; v[6] = normals[i*3+2]; }
        else { v[4] = 0; v[5] = 0; v[6] = 0; }
        v[7] = 0;
        if (tangents) { v[8] = tangents[i*4]; v[9] = tangents[i*4+1]; v[10] = tangents[i*4+2]; v[11] = tangents[i*4+3]; }
        else { v[8] = 1; v[9] = 0; v[10] = 0; v[11] = 1; }
        if (colors) {
            const float *c = colors + i * colorComponents;
            v[12] = c[0]; v[13] = c[1]; v[14] = c[2]; v[15] = colorComponents == 4 ? c[3] : 1;
        } else { v[12] = 1; v[13] = 1; v[14] = 1; v[15] = 1; }
        if (uv0) { v[16] = uv0[i*2]; v[17] = uv0[i*2+1]; } else { v[16] = 0; v[17] = 0; }
        if (uv1) { v[18] = uv1[i*2]; v[19] = uv1[i*2+1]; } else { v[18] = 0; v[19] = 0; }
    }
}

bool GLTFMetalWidenIndices(const void *source, size_t width, size_t count, uint32_t *destination, size_t vertexCount) {
    uint32_t largest = 0;
    for (size_t i = 0; i < count; ++i) {
        uint32_t value;
        switch (width) {
        case 1: value = ((const uint8_t *)source)[i]; break;
        case 2: { uint16_t v; memcpy(&v, (const uint8_t *)source + i * 2, 2); value = v; break; }
        default: memcpy(&value, (const uint8_t *)source + i * 4, 4); break;
        }
        destination[i] = value;
        if (value > largest) largest = value;
    }
    return count == 0 || largest < vertexCount;
}

void GLTFMetalSequentialIndices(uint32_t *destination, size_t count) {
    for (size_t i = 0; i < count; ++i) destination[i] = (uint32_t)i;
}

void GLTFMetalGatherVertices(float *destination, const float *source, const uint32_t *indices, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        memcpy(destination + i * VertexFloats, source + (size_t)indices[i] * VertexFloats, VertexFloats * sizeof(float));
    }
}

void GLTFMetalFlatNormals(float *destination, const float *source, const uint32_t *indices, size_t count) {
    GLTFMetalGatherVertices(destination, source, indices, count);
    for (size_t i = 0; i + 2 < count; i += 3) {
        float *a = destination + i * VertexFloats, *b = a + VertexFloats, *c = b + VertexFloats;
        const simd_float4 pa = simd_make_float4(a[0], a[1], a[2], a[3]);
        const simd_float4 e1 = simd_make_float4(b[0], b[1], b[2], b[3]) - pa;
        const simd_float4 e2 = simd_make_float4(c[0], c[1], c[2], c[3]) - pa;
        const simd_float3 cross = simd_cross(simd_make_float3(e1.x, e1.y, e1.z), simd_make_float3(e2.x, e2.y, e2.z));
        const simd_float3 n = simd_length_squared(cross) > 0 ? simd_normalize(cross) : simd_make_float3(0, 0, 1);
        float *corners[3] = { a, b, c };
        for (int k = 0; k < 3; ++k) { corners[k][4] = n.x; corners[k][5] = n.y; corners[k][6] = n.z; corners[k][7] = 0; }
    }
}

void GLTFMetalBounds(const float *vertices, size_t count, const float *model, float *minimum, float *maximum) {
    simd_float4x4 m;
    memcpy(&m, model, sizeof m);
    simd_float3 lo = simd_make_float3(minimum[0], minimum[1], minimum[2]);
    simd_float3 hi = simd_make_float3(maximum[0], maximum[1], maximum[2]);
    for (size_t i = 0; i < count; ++i) {
        const float *v = vertices + i * VertexFloats;
        const simd_float4 p = simd_mul(m, simd_make_float4(v[0], v[1], v[2], v[3]));
        const simd_float3 q = simd_make_float3(p.x, p.y, p.z);
        lo = simd_min(lo, q); hi = simd_max(hi, q);
    }
    minimum[0] = lo.x; minimum[1] = lo.y; minimum[2] = lo.z;
    maximum[0] = hi.x; maximum[1] = hi.y; maximum[2] = hi.z;
}
