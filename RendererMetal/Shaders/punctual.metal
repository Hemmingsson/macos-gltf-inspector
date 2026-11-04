// Hand port of glTF-Sample-Renderer 863b981 punctual.glsl (Apache-2.0).
#ifndef GLTF_METAL_PUNCTUAL
#define GLTF_METAL_PUNCTUAL
#include "ShaderTypes.metalh"
#include "brdf.metal"
inline float getRangeAttenuation(float range,float distance) {
    if(range<=0.0f) return 1.0f/(distance*distance);
    return clamp(1.0f-pow(distance/range,4.0f),0.0f,1.0f)/(distance*distance);
}
inline float getSpotAttenuation(float3 pointToLight,float3 direction,float outer,float inner) {
    float actualCos=dot(normalize(direction),normalize(-pointToLight));
    if(actualCos>outer) {
        if(actualCos<inner) { float a=(actualCos-outer)/(inner-outer); return a*a; }
        return 1.0f;
    }
    return 0.0f;
}
inline float3 getLightIntensity(MetalLight light,float3 pointToLight) {
    uint type=uint(light.outerType.y);
    float attenuation=type==0 ? 1.0f : getRangeAttenuation(light.directionRange.w,length(pointToLight));
    if(type==2) attenuation*=getSpotAttenuation(pointToLight,light.directionRange.xyz,light.outerType.x,light.positionInnerCone.w);
    return attenuation*light.colorIntensity.w*light.colorIntensity.rgb;
}
inline float3 applyVolumeAttenuation(float3 radiance,float distance,float3 color,float attenuationDistance) {
    return attenuationDistance==0.0f ? radiance : pow(color,float3(distance/attenuationDistance))*radiance;
}
inline float3 getVolumeTransmissionRay(float3 n,float3 v,float thickness,float ior,float4x4 model) {
    float3 ray=refract(-v,normalize(n),1.0f/ior);
    return normalize(ray)*thickness*float3(length(model[0].xyz),length(model[1].xyz),length(model[2].xyz));
}
inline float3 getPunctualRadianceTransmission(float3 normal,float3 view,float3 pointToLight,float alphaRoughness,float3 baseColor,float ior) {
    float roughness=alphaRoughness*clamp(ior*2.0f-2.0f,0.0f,1.0f);
    float3 n=normalize(normal),v=normalize(view),l=normalize(pointToLight);
    float3 mirror=normalize(l+2.0f*n*dot(-l,n)),h=normalize(mirror+v);
    float D=D_GGX(clamp(dot(n,h),0.0f,1.0f),roughness);
    float visibility=V_GGX(clamp(dot(n,mirror),0.0f,1.0f),clamp(dot(n,v),0.0f,1.0f),roughness);
    return baseColor*D*visibility;
}

#endif
