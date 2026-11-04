#ifndef MetalLoadKernels_h
#define MetalLoadKernels_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Hot per-texel and per-vertex loops of the native scene loader. They live in C so that a Debug
// build (the bench and tests) does not pay Swift's unoptimised array and SIMD overhead. Each one
// does exactly the arithmetic the former Swift loop did; outputs are byte-identical.

/// Straight 8-bit RGB(A) rows (`components` 3 or 4) to tightly packed RGBA8. Alpha is copied when
/// `keepAlpha`, else 255.
void GLTFMetalExpandRGBA8(const uint8_t *source, size_t sourceBytesPerRow, size_t components, bool keepAlpha,
                          size_t width, size_t height, uint8_t *destination);
/// Premultiplied RGBA8 to straight alpha in place: c = min(255, (c * 255 + a / 2) / a) for 0 < a < 255.
void GLTFMetalUnpremultiplyRGBA8(uint8_t *pixels, size_t pixelCount);

/// Interleaves float accessors into 80-byte `MetalVertex` records. Absent inputs are NULL and take
/// the loader defaults: normal 0, tangent (1,0,0,1), colour 1 (alpha 1 when RGB), UVs 0.
void GLTFMetalPackVertices(float *vertices, size_t count, const float *positions, const float *normals,
                           const float *tangents, const float *colors, size_t colorComponents,
                           const float *uv0, const float *uv1);
/// Widens 1/2/4-byte indices to UInt32. False when any index is >= vertexCount.
bool GLTFMetalWidenIndices(const void *source, size_t width, size_t count, uint32_t *destination, size_t vertexCount);
/// 0, 1, 2, ... count-1.
void GLTFMetalSequentialIndices(uint32_t *destination, size_t count);
/// destination[i] = source[indices[i]] for 80-byte vertices.
void GLTFMetalGatherVertices(float *destination, const float *source, const uint32_t *indices, size_t count);
/// Deindexed triangles with one face normal per triangle (count = whole triangles * 3 indices).
void GLTFMetalFlatNormals(float *destination, const float *source, const uint32_t *indices, size_t count);
/// Expands min/max (xyz) by model * position of each vertex; model is column-major 4x4.
void GLTFMetalBounds(const float *vertices, size_t count, const float *model, float *minimum, float *maximum);

#endif
