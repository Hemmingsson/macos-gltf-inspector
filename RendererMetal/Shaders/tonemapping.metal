// Hand port of glTF-Sample-Renderer 863b981 tonemapping.glsl (Apache-2.0).
#ifndef GLTF_METAL_TONEMAPPING
#define GLTF_METAL_TONEMAPPING
#include <metal_stdlib>
using namespace metal;
inline float3 linearTosRGB(float3 color) { return pow(color,float3(1.0f/2.2f)); }
inline float3 toneMap_KhronosPbrNeutral(float3 color) {
    const float startCompression=0.8f-0.04f, desaturation=0.15f;
    float x=min(color.r,min(color.g,color.b));
    float offset=x<0.08f ? x-6.25f*x*x : 0.04f;
    color-=offset;
    float peak=max(color.r,max(color.g,color.b));
    if(peak<startCompression) return color;
    float d=1.0f-startCompression;
    float newPeak=1.0f-d*d/(peak+d-startCompression);
    color*=newPeak/peak;
    float g=1.0f-1.0f/(desaturation*(peak-newPeak)+1.0f);
    return mix(color,float3(newPeak),g);
}
inline float3 toneMapACES_Narkowicz(float3 color) {
    return clamp((color*(2.51f*color+0.03f))/(color*(2.43f*color+0.59f)+0.14f),0.0f,1.0f);
}
inline float3 RRTAndODTFit(float3 color) {
    return (color*(color+0.0245786f)-0.000090537f)/(color*(0.983729f*color+0.4329510f)+0.238081f);
}
inline float3 toneMapACES_Hill(float3 color) {
    const float3x3 input(float3(0.59719f,0.07600f,0.02840f),float3(0.35458f,0.90834f,0.13383f),float3(0.04823f,0.01566f,0.83777f));
    const float3x3 output(float3(1.60475f,-0.10208f,-0.00327f),float3(-0.53108f,1.10813f,-0.07276f),float3(-0.07367f,-0.00605f,1.07602f));
    return clamp(output*RRTAndODTFit(input*color),0.0f,1.0f);
}
inline float3 toneMap(float3 color,float exposure,uint mode) {
    color*=exposure;
    if(mode==0) color=toneMap_KhronosPbrNeutral(color);
    else if(mode==2) color=toneMapACES_Narkowicz(color);
    else if(mode==3) color=toneMapACES_Hill(color);
    else if(mode==4) color=toneMapACES_Hill(color/0.6f);
    return linearTosRGB(color);
}
#endif
