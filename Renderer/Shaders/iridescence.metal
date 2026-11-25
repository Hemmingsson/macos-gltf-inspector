// Hand port of glTF-Sample-Renderer 863b981 iridescence.glsl (Apache-2.0).
#ifndef GLTF_METAL_IRIDESCENCE
#define GLTF_METAL_IRIDESCENCE
#include "brdf.metal"
inline float3 Fresnel0ToIor(float3 f0) { float3 s=sqrt(f0); return (1.0f+s)/(1.0f-s); }
inline float3 IorToFresnel0(float3 ior,float incident) { float3 x=(ior-incident)/(ior+incident); return x*x; }
inline float IorToFresnel0(float ior,float incident) { float x=(ior-incident)/(ior+incident); return x*x; }
inline float3 evalSensitivity(float OPD,float3 shift) {
    float phase=2.0f*kPi*OPD*1.0e-9f;
    float3 val(5.4856e-13f,4.4201e-13f,5.2481e-13f);
    float3 pos(1.6810e6f,1.7953e6f,2.2084e6f);
    float3 variance(4.3278e9f,9.3046e9f,6.6121e9f);
    float3 xyz=val*sqrt(2.0f*kPi*variance)*cos(pos*phase+shift)*exp(-phase*phase*variance);
    xyz.x+=9.7470e-14f*sqrt(2.0f*kPi*4.5282e9f)*cos(2.2399e6f*phase+shift.x)*exp(-4.5282e9f*phase*phase);
    xyz/=1.0685e-7f;
    const float3x3 XYZ_TO_REC709(float3(3.2404542f,-0.9692660f,0.0556434f),float3(-1.5371385f,1.8760108f,-0.2040259f),float3(-0.4985314f,0.0415560f,1.0572252f));
    return XYZ_TO_REC709*xyz;
}
inline float3 evalIridescence(float outsideIOR,float eta2,float cosTheta1,float thickness,float3 baseF0) {
    float ior=mix(outsideIOR,eta2,smoothstep(0.0f,0.03f,thickness));
    float ratio=outsideIOR/ior;
    float cosTheta2Sq=1.0f-ratio*ratio*(1.0f-cosTheta1*cosTheta1);
    if(cosTheta2Sq<0.0f) return float3(1);
    float cosTheta2=sqrt(cosTheta2Sq);
    float R0=IorToFresnel0(ior,outsideIOR);
    float R12=F_Schlick(float3(R0),cosTheta1).x;
    float T121=1.0f-R12;
    float phi12=ior<outsideIOR ? kPi : 0.0f;
    float phi21=kPi-phi12;
    float3 baseIOR=Fresnel0ToIor(clamp(baseF0,0.0f,0.9999f));
    float3 R23=F_Schlick(IorToFresnel0(baseIOR,ior),cosTheta2);
    float3 phi23=select(float3(0),float3(kPi),baseIOR<float3(ior));
    float OPD=2.0f*ior*thickness*cosTheta2;
    float3 phi=phi21+phi23;
    float3 R123=clamp(R12*R23,1e-5f,0.9999f);
    float3 r123=sqrt(R123);
    float3 Rs=T121*T121*R23/(1.0f-R123);
    float3 I=R12+Rs;
    float3 Cm=Rs-T121;
    for(int m=1;m<=2;++m) { Cm*=r123; I+=Cm*2.0f*evalSensitivity(float(m)*OPD,float(m)*phi); }
    return max(I,0.0f);
}
#endif
