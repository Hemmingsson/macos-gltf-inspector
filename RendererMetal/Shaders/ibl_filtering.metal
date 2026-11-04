// Hand port of glTF-Sample-Renderer 863b981 ibl_filtering.frag.
// The compute wrapper writes cubemap-face array views; integrals match upstream.
#include <metal_stdlib>
using namespace metal;
namespace khronos_filter {
constant float pi=3.1415926535897932384626433832795f;
struct FilterUniforms {
    uint distribution;
    uint sampleCount;
    float roughness;
    float lodBias;
    float intensityScale;
    uint sourceWidth;
    uint pad0;
    uint pad1;
};
inline float radicalInverse_VdC(uint bits) {
    bits=(bits<<16u)|(bits>>16u);
    bits=((bits&0x55555555u)<<1u)|((bits&0xAAAAAAAAu)>>1u);
    bits=((bits&0x33333333u)<<2u)|((bits&0xCCCCCCCCu)>>2u);
    bits=((bits&0x0F0F0F0Fu)<<4u)|((bits&0xF0F0F0F0u)>>4u);
    bits=((bits&0x00FF00FFu)<<8u)|((bits&0xFF00FF00u)>>8u);
    return float(bits)*2.3283064365386963e-10f;
}
inline float2 hammersley2d(uint i,uint count) { return float2(float(i)/float(count),radicalInverse_VdC(i)); }
inline float3x3 generateTBN(float3 normal) {
    float3 bitangent(0,1,0);
    float NdotUp=dot(normal,float3(0,1,0));
    if(1.0f-abs(NdotUp)<=0.0000001f) bitangent=NdotUp>0 ? float3(0,0,1) : float3(0,0,-1);
    float3 tangent=normalize(cross(bitangent,normal));
    bitangent=cross(normal,tangent);
    return float3x3(tangent,bitangent,normal);
}
inline float D_GGX(float NdotH,float roughness) {
    float a=NdotH*roughness;
    float k=roughness/(1.0f-NdotH*NdotH+a*a);
    return k*k/pi;
}
inline float D_Charlie(float roughness,float NdotH) {
    roughness=max(roughness,0.000001f);
    float invR=1.0f/roughness;
    return (2.0f+invR)*pow(1.0f-NdotH*NdotH,invR*0.5f)/(2.0f*pi);
}
struct DistributionSample { float pdf; float cosTheta; float sinTheta; float phi; };
inline DistributionSample GGX(float2 xi,float roughness) {
    float alpha=roughness*roughness;
    float cosTheta=clamp(sqrt((1.0f-xi.y)/(1.0f+(alpha*alpha-1.0f)*xi.y)),0.0f,1.0f);
    return {D_GGX(cosTheta,alpha)/4.0f,cosTheta,sqrt(1.0f-cosTheta*cosTheta),2.0f*pi*xi.x};
}
inline DistributionSample Charlie(float2 xi,float roughness) {
    float alpha=roughness*roughness;
    float sinTheta=pow(xi.y,alpha/(2.0f*alpha+1.0f));
    float cosTheta=sqrt(1.0f-sinTheta*sinTheta);
    return {D_Charlie(alpha,cosTheta)/4.0f,cosTheta,sinTheta,2.0f*pi*xi.x};
}
inline DistributionSample Lambertian(float2 xi) {
    float cosTheta=sqrt(1.0f-xi.y);
    return {cosTheta/pi,cosTheta,sqrt(xi.y),2.0f*pi*xi.x};
}
inline float4 getImportanceSample(uint index,float3 N,float roughness,constant FilterUniforms &u) {
    float2 xi=hammersley2d(index,u.sampleCount);
    DistributionSample d;
    if(u.distribution==0) d=Lambertian(xi);
    else if(u.distribution==1) d=GGX(xi,roughness);
    else d=Charlie(xi,roughness);
    float3 local=normalize(float3(d.sinTheta*cos(d.phi),d.sinTheta*sin(d.phi),d.cosTheta));
    return float4(generateTBN(N)*local,d.pdf);
}
inline float3 cubeDirection(uint face,float2 uv) {
    // Metal cube array slice order +X,-X,+Y,-Y,+Z,-Z; texel row zero is top.
    float2 p=uv*2.0f-1.0f;
    if(face==0) return normalize(float3(1,-p.y,-p.x));
    if(face==1) return normalize(float3(-1,-p.y,p.x));
    if(face==2) return normalize(float3(p.x,1,p.y));
    if(face==3) return normalize(float3(p.x,-1,-p.y));
    if(face==4) return normalize(float3(p.x,-p.y,1));
    return normalize(float3(-p.x,-p.y,-1));
}
inline float3 filterColor(float3 N,texturecube<float> source,constant FilterUniforms &u) {
    constexpr sampler cubeSampler(coord::normalized,address::clamp_to_edge,filter::linear,mip_filter::linear);
    float3 color(0); float weight=0;
    for(uint i=0;i<u.sampleCount;++i) {
        float4 importanceSample=getImportanceSample(i,N,u.roughness,u);
        float3 H=importanceSample.xyz;
        float lod=0.5f*log2(6.0f*float(u.sourceWidth)*float(u.sourceWidth)/(float(u.sampleCount)*importanceSample.w))+u.lodBias;
        if(u.distribution==0) color+=source.sample(cubeSampler,H,level(lod)).rgb*u.intensityScale;
        else {
            float3 L=normalize(reflect(-N,H));
            float NdotL=dot(N,L);
            if(NdotL>0) {
                if(u.roughness==0) lod=u.lodBias;
                color+=source.sample(cubeSampler,L,level(lod)).rgb*u.intensityScale*NdotL;
                weight+=NdotL;
            }
        }
    }
    return weight!=0 ? color/weight : color/float(u.sampleCount);
}
inline float V_SmithGGXCorrelated(float NoV,float NoL,float roughness) {
    float a2=pow(roughness,4.0f);
    float GGXV=NoL*sqrt(NoV*NoV*(1.0f-a2)+a2);
    float GGXL=NoV*sqrt(NoL*NoL*(1.0f-a2)+a2);
    return 0.5f/(GGXV+GGXL);
}
inline float V_Ashikhmin(float NdotL,float NdotV) { return clamp(1.0f/(4.0f*(NdotL+NdotV-NdotL*NdotV)),0.0f,1.0f); }
inline float3 LUT(float NdotV,float roughness,constant FilterUniforms &u) {
    float3 V(sqrt(1.0f-NdotV*NdotV),0,NdotV),N(0,0,1);
    float A=0,B=0,C=0;
    for(uint i=0;i<u.sampleCount;++i) {
        float3 H=getImportanceSample(i,N,roughness,u).xyz;
        float3 L=normalize(reflect(-V,H));
        float NdotL=clamp(L.z,0.0f,1.0f),NdotH=clamp(H.z,0.0f,1.0f),VdotH=clamp(dot(V,H),0.0f,1.0f);
        if(NdotL>0) {
            if(u.distribution==1) {
                float V_pdf=V_SmithGGXCorrelated(NdotV,NdotL,roughness)*VdotH*NdotL/NdotH;
                float Fc=pow(1.0f-VdotH,5.0f);
                A+=(1.0f-Fc)*V_pdf; B+=Fc*V_pdf;
            } else if(u.distribution==2) {
                C+=V_Ashikhmin(NdotL,NdotV)*D_Charlie(roughness,NdotH)*NdotL*VdotH;
            }
        }
    }
    return float3(4.0f*A,4.0f*B,8.0f*pi*C)/float(u.sampleCount);
}
} // namespace
kernel void khronos_panorama_to_cube(texture2d<float> panorama [[texture(0)]],
    texture2d_array<float,access::write> destination [[texture(1)]],
    constant float &intensityScale [[buffer(0)]],uint3 gid [[thread_position_in_grid]]) {
    if(gid.x>=destination.get_width() || gid.y>=destination.get_height() || gid.z>=6) return;
    float2 uv=(float2(gid.xy)+0.5f)/float2(destination.get_width(),destination.get_height());
    float3 direction=khronos_filter::cubeDirection(gid.z,uv);
    float2 panoUV(0.5f+0.5f*atan2(direction.z,direction.x)/khronos_filter::pi,acos(clamp(direction.y,-1.0f,1.0f))/khronos_filter::pi);
    constexpr sampler panoramaSampler(coord::normalized,s_address::repeat,t_address::clamp_to_edge,filter::linear);
    destination.write(float4(panorama.sample(panoramaSampler,panoUV).rgb*intensityScale,1),gid.xy,gid.z);
}
kernel void khronos_ibl_filter(texturecube<float> source [[texture(0)]],
    texture2d_array<float,access::write> destination [[texture(1)]],
    constant khronos_filter::FilterUniforms &u [[buffer(0)]],uint3 gid [[thread_position_in_grid]]) {
    if(gid.x>=destination.get_width() || gid.y>=destination.get_height() || gid.z>=6) return;
    float2 uv=(float2(gid.xy)+0.5f)/float2(destination.get_width(),destination.get_height());
    float3 color=khronos_filter::filterColor(khronos_filter::cubeDirection(gid.z,uv),source,u);
    destination.write(float4(color,1),gid.xy,gid.z);
}
kernel void khronos_ibl_lut(texture2d<float,access::write> destination [[texture(0)]],
    constant khronos_filter::FilterUniforms &u [[buffer(0)]],uint2 gid [[thread_position_in_grid]]) {
    if(gid.x>=destination.get_width() || gid.y>=destination.get_height()) return;
    float2 uv=(float2(gid)+0.5f)/float2(destination.get_width(),destination.get_height());
    destination.write(float4(khronos_filter::LUT(uv.x,uv.y,u),1),gid);
}
