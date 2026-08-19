#include <metal_stdlib>
using namespace metal;

// Khronos Sample Renderer curves (tonemapping.glsl + PBR Neutral).
// Linear Rec.709 in; linear Rec.709 in [0, 1] after the curve; then ~sRGB.

constant float3x3 kACESInputMat = float3x3(
    float3(0.59719, 0.07600, 0.02840),
    float3(0.35458, 0.90834, 0.13383),
    float3(0.04823, 0.01566, 0.83777)
);

constant float3x3 kACESOutputMat = float3x3(
    float3(1.60475, -0.10208, -0.00327),
    float3(-0.53108, 1.10813, -0.07276),
    float3(-0.07367, -0.00605, 1.07602)
);

struct ToneMapParams {
    float exposure;
    uint mode;
};

static float3 linearToSRGB(float3 color) {
    return pow(color, float3(1.0 / 2.2));
}

static float3 toneMapACES_Narkowicz(float3 color) {
    const float A = 2.51;
    const float B = 0.03;
    const float C = 2.43;
    const float D = 0.59;
    const float E = 0.14;
    return saturate((color * (A * color + B)) / (color * (C * color + D) + E));
}

static float3 RRTAndODTFit(float3 color) {
    float3 a = color * (color + 0.0245786) - 0.000090537;
    float3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
    return a / b;
}

static float3 toneMapACES_Hill(float3 color) {
    color = kACESInputMat * color;
    color = RRTAndODTFit(color);
    color = kACESOutputMat * color;
    return saturate(color);
}

static float3 toneMap_KhronosPbrNeutral(float3 color) {
    const float startCompression = 0.8 - 0.04;
    const float desaturation = 0.15;

    float x = min(color.r, min(color.g, color.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    color -= offset;

    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) {
        return color;
    }

    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    color *= newPeak / peak;

    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return mix(color, newPeak * float3(1.0, 1.0, 1.0), g);
}

static float3 applyToneMap(float3 color, uint mode) {
    switch (mode) {
    case 1:
        color /= 0.6;
        return toneMapACES_Hill(color);
    case 2:
        return toneMapACES_Narkowicz(color);
    case 3:
        return toneMapACES_Hill(color);
    case 4:
        return saturate(color);
    default:
        return toneMap_KhronosPbrNeutral(color);
    }
}

kernel void toneMapPostProcess(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant ToneMapParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) {
        return;
    }

    float4 sample = source.read(gid);
    float3 linearHDR = max(sample.rgb, float3(0.0)) * params.exposure;
    float3 mapped = applyToneMap(linearHDR, params.mode);
    destination.write(float4(linearToSRGB(mapped), sample.a), gid);
}
