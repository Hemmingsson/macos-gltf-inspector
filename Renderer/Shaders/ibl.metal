// Hand port of glTF-Sample-Renderer 863b981 ibl.glsl (Apache-2.0).
#ifndef GLTF_METAL_IBL
#define GLTF_METAL_IBL
#include "brdf.metal"
inline float3 rotateEnvironment(float3 direction,float radians) {
    float s=sin(radians), c=cos(radians);
    return float3(c*direction.x+s*direction.z,direction.y,-s*direction.x+c*direction.z);
}
inline float3 getIBLGGXFresnel(float NdotV,float roughness,float3 F0,float weight,float2 f_ab) {
    float3 Fr=max(float3(1.0f-roughness),F0)-F0;
    float3 k_S=F0+Fr*pow(1.0f-NdotV,5.0f);
    float3 FssEss=weight*(k_S*f_ab.x+f_ab.y);
    float Ems=1.0f-(f_ab.x+f_ab.y);
    float3 F_avg=weight*(F0+(1.0f-F0)/21.0f);
    float3 FmsEms=Ems*FssEss*F_avg/(1.0f-F_avg*Ems);
    return FssEss+FmsEms;
}
inline float3 anisotropicBentNormal(float3 n,float3 v,float roughness,float anisotropy,float3 direction) {
    float3 tangent=cross(direction,v);
    float3 anisotropicNormal=cross(tangent,direction);
    float bend=1.0f-anisotropy*(1.0f-roughness);
    float bend4=bend*bend*bend*bend;
    return normalize(mix(anisotropicNormal,n,bend4));
}
#endif
