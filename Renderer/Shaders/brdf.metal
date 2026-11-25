// Hand port of glTF-Sample-Renderer 863b981 brdf.glsl (Apache-2.0).
#ifndef GLTF_METAL_BRDF
#define GLTF_METAL_BRDF
#include <metal_stdlib>
using namespace metal;
constant float kPi = 3.14159265358979323846f;
inline float3 F_Schlick(float3 f0, float3 f90, float VdotH) {
    return f0 + (f90-f0)*pow(clamp(1.0f-VdotH,0.0f,1.0f),5.0f);
}
inline float3 F_Schlick(float3 f0, float VdotH) { return F_Schlick(f0,float3(1),VdotH); }
inline float V_GGX(float NdotL,float NdotV,float alphaRoughness) {
    float a2=alphaRoughness*alphaRoughness;
    float GGXV=NdotL*sqrt(NdotV*NdotV*(1.0f-a2)+a2);
    float GGXL=NdotV*sqrt(NdotL*NdotL*(1.0f-a2)+a2);
    float sum=GGXV+GGXL;
    return sum>0.0f ? 0.5f/sum : 0.0f;
}
inline float D_GGX(float NdotH,float alphaRoughness) {
    float a2=alphaRoughness*alphaRoughness;
    float f=NdotH*NdotH*(a2-1.0f)+1.0f;
    return a2/(kPi*f*f);
}
inline float3 BRDF_lambertian(float3 diffuseColor) { return diffuseColor/kPi; }
inline float3 BRDF_specularGGX(float alphaRoughness,float NdotL,float NdotV,float NdotH) {
    return float3(V_GGX(NdotL,NdotV,alphaRoughness)*D_GGX(NdotH,alphaRoughness));
}
inline float lambdaSheenNumericHelper(float x,float alphaG) {
    float a2=(1.0f-alphaG)*(1.0f-alphaG);
    float a=mix(21.5473f,25.3245f,a2), b=mix(3.82987f,3.32435f,a2);
    float c=mix(0.19823f,0.16801f,a2), d=mix(-1.97760f,-1.27393f,a2);
    float e=mix(-4.32054f,-4.85967f,a2);
    return a/(1.0f+b*pow(x,c))+d*x+e;
}
inline float lambdaSheen(float cosTheta,float alphaG) {
    return abs(cosTheta)<0.5f ? exp(lambdaSheenNumericHelper(cosTheta,alphaG))
      : exp(2.0f*lambdaSheenNumericHelper(0.5f,alphaG)-lambdaSheenNumericHelper(1.0f-cosTheta,alphaG));
}
inline float V_Sheen(float NdotL,float NdotV,float roughness) {
    roughness=max(roughness,0.000001f);
    float a=roughness*roughness;
    return clamp(1.0f/((1.0f+lambdaSheen(NdotV,a)+lambdaSheen(NdotL,a))*4.0f*NdotV*NdotL),0.0f,1.0f);
}
inline float D_Charlie(float roughness,float NdotH) {
    roughness=max(roughness,0.000001f);
    float invR=1.0f/(roughness*roughness);
    return (2.0f+invR)*pow(1.0f-NdotH*NdotH,invR*0.5f)/(2.0f*kPi);
}
inline float3 BRDF_specularSheen(float3 color,float roughness,float NdotL,float NdotV,float NdotH) {
    return color*D_Charlie(roughness,NdotH)*V_Sheen(NdotL,NdotV,roughness);
}
inline float D_GGX_anisotropic(float NdotH,float TdotH,float BdotH,float at,float ab) {
    float a2=at*ab;
    float3 f=float3(ab*TdotH,at*BdotH,a2*NdotH);
    float w2=a2/dot(f,f);
    return a2*w2*w2/kPi;
}
inline float V_GGX_anisotropic(float NdotL,float NdotV,float BdotV,float TdotV,float TdotL,float BdotL,float at,float ab) {
    float GGXV=NdotL*length(float3(at*TdotV,ab*BdotV,NdotV));
    float GGXL=NdotV*length(float3(at*TdotL,ab*BdotL,NdotL));
    return clamp(0.5f/(GGXV+GGXL),0.0f,1.0f);
}
inline float3 BRDF_specularGGXAnisotropy(float roughness,float anisotropy,float3 n,float3 v,float3 l,float3 h,float3 t,float3 b) {
    float at=mix(roughness,1.0f,anisotropy*anisotropy), ab=clamp(roughness,0.001f,1.0f);
    float nl=clamp(dot(n,l),0.0f,1.0f), nh=clamp(dot(n,h),0.001f,1.0f);
    return float3(V_GGX_anisotropic(nl,dot(n,v),dot(b,v),dot(t,v),dot(t,l),dot(b,l),at,ab)
        *D_GGX_anisotropic(nh,dot(t,h),dot(b,h),at,ab));
}
#endif
