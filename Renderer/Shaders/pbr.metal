// Hand port of the Khronos glTF Sample Renderer 863b981. See UPSTREAM.md.
#include "ShaderTypes.metalh"
#include "brdf.metal"
#include "ibl.metal"
#include "punctual.metal"
#include "iridescence.metal"
#include "tonemapping.metal"

struct MetalVaryings {
    float4 position [[position, invariant]];
    float3 worldPosition;
    float3 normal;
    float4 tangent;
    float3 bitangent;
    float4 color;
    float2 uv0;
    float2 uv1;
};
inline float3 rgb_mix(float3 base,float3 layer,float3 alpha) { return (1.0f-max(alpha.r,max(alpha.g,alpha.b)))*base+alpha*layer; }
struct MetalFragmentOutput { float4 color [[color(0)]]; uint toneMapFlag [[color(1)]]; };
// Zero mask, no capture and no skin compiles out, so a rigid draw stays the unmorphed shader.
constant uint morph_mask [[function_constant(0)]];
constant bool morph_capture [[function_constant(1)]];
constant bool morph_streams [[function_constant(2)]];
constant bool has_skin [[function_constant(3)]];
constant bool has_joints1 [[function_constant(4)]];
struct SkinVertex {
    ushort4 joints0;
    ushort4 joints1;
    float4 weights0;
    float4 weights1;
};
struct JointPair {
    float4x4 joint;
    float4x4 normal;
};
float4 morph_sum(uint slot,uint vid,constant float *weights,device const float4 *morphs,constant MetalDrawUniforms &draw) {
    uint targets=draw.morphInfo.x, verts=draw.morphInfo.y;
    uint ordinal=uint(popcount(morph_mask & ((1u<<slot)-1u)));
    float4 sum=float4(0);
    for(uint t=0;t<targets;++t) sum+=weights[t]*morphs[(ordinal*targets+t)*verts+vid];
    return sum;
}
vertex MetalVaryings khronos_vertex(uint id [[vertex_id]],
    device const MetalVertex *vertices [[buffer(0)]],
    constant MetalFrameUniforms &frame [[buffer(1)]],
    constant MetalDrawUniforms &draw [[buffer(2)]],
    constant MetalMaterialUniforms &m [[buffer(3)]],
    device const float4 *morphs [[buffer(4), function_constant(morph_streams)]],
    constant float *weights [[buffer(5), function_constant(morph_streams)]],
    device MetalVertex *capture [[buffer(6), function_constant(morph_capture)]],
    device const SkinVertex *skinVerts [[buffer(7), function_constant(has_skin)]],
    constant JointPair *jointPairs [[buffer(8), function_constant(has_skin)]]) {
    MetalVertex v=vertices[id];
    float3 pos=v.position.xyz;
    float3 nrm=v.normal.xyz;
    float4 tan=v.tangent;
    float4 col=v.color;
    float2 uv0=v.uv0, uv1=v.uv1;
    // Morph deltas first, then skin. Skinning the already-morphed vertex is R·(v+d).
    if(morph_streams) {
        if(morph_mask&1u) pos+=morph_sum(0,id,weights,morphs,draw).xyz;
        if(morph_mask&2u) nrm+=morph_sum(1,id,weights,morphs,draw).xyz;
        if(morph_mask&4u) tan.xyz+=morph_sum(2,id,weights,morphs,draw).xyz;
        if(morph_mask&8u) uv0+=morph_sum(3,id,weights,morphs,draw).xy;
        if(morph_mask&16u) uv1+=morph_sum(4,id,weights,morphs,draw).xy;
        if(morph_mask&32u) col=clamp(col+morph_sum(5,id,weights,morphs,draw),0.0f,1.0f);
    }
    if(has_skin) {
        SkinVertex s=skinVerts[id];
        uint jointCount=draw.morphInfo.w;
        float4x4 skinM=float4x4(0.0f);
        float4x4 skinN=float4x4(0.0f);
        float wsum=0.0f;
        for(int i=0;i<4;++i) {
            float w=s.weights0[i];
            uint j=s.joints0[i];
            if(w!=0.0f && j<jointCount) { skinM+=jointPairs[j].joint*w; skinN+=jointPairs[j].normal*w; wsum+=w; }
        }
        if(has_joints1) {
            for(int i=0;i<4;++i) {
                float w=s.weights1[i];
                uint j=s.joints1[i];
                if(w!=0.0f && j<jointCount) { skinM+=jointPairs[j].joint*w; skinN+=jointPairs[j].normal*w; wsum+=w; }
            }
        }
        // A zero weight sum is the identity: the vertex stays in bind space.
        if(wsum!=0.0f) {
            pos=(skinM*float4(pos,1.0f)).xyz;
            nrm=(skinN*float4(nrm,0.0f)).xyz;
            tan.xyz=(skinM*float4(tan.xyz,0.0f)).xyz;
        }
    }
    if(morph_capture) {
        MetalVertex c=v;
        c.position=float4(pos,v.position.w); c.normal=float4(nrm,v.normal.w); c.tangent=tan;
        c.color=col; c.uv0=uv0; c.uv1=uv1;
        capture[id]=c;
    }
    MetalVaryings o;
    // Skinned positions are already in world space (joint world * inverse bind). The mesh node's
    // model matrix is not applied. Normals still get that node's normal matrix; tangents get model.
    float4 p=has_skin ? float4(pos,1) : draw.model*float4(pos,1);
    o.position=frame.viewProjection*p;
    o.position.z=(o.position.z+o.position.w)*0.5f;
    o.worldPosition=p.xyz/p.w;
    o.normal=normalize((draw.normalMatrix*float4(nrm,0)).xyz);
    float3 tangentW=(draw.model*float4(tan.xyz,0)).xyz;
    float3 bitangentW=cross(o.normal,tangentW)*tan.w;
    float3 uvT=float3(dot(m.uvTransforms[6].xyz,tangentW),dot(m.uvTransforms[7].xyz,tangentW),dot(m.uvTransforms[8].xyz,tangentW));
    float3 uvB=float3(dot(m.uvTransforms[6].xyz,bitangentW),dot(m.uvTransforms[7].xyz,bitangentW),dot(m.uvTransforms[8].xyz,bitangentW));
    o.bitangent=normalize(uvB);
    o.tangent=float4(normalize(uvT),tan.w);
    o.color=col; o.uv0=uv0; o.uv1=uv1;
    return o;
}
fragment float4 khronos_capture_fragment(MetalVaryings in [[stage_in]]) { return float4(0); }
inline float2 materialUV(MetalVaryings in,constant MetalMaterialUniforms &m,uint slot) {
    uint set=m.uvSets[slot/4][slot%4];
    float3 uv=float3(set==1 ? in.uv1 : in.uv0,1);
    return float2(dot(m.uvTransforms[slot*3].xyz,uv),dot(m.uvTransforms[slot*3+1].xyz,uv));
}
fragment MetalFragmentOutput khronos_fragment(MetalVaryings in [[stage_in]],bool front [[front_facing]],
    constant MetalFrameUniforms &frame [[buffer(1)]],
    constant MetalDrawUniforms &draw [[buffer(2)]],
    constant MetalMaterialUniforms &m [[buffer(3)]],
    device const MetalLight *lights [[buffer(4)]],
    constant MaterialTextureArguments &materialTextures [[buffer(5)]],
    texturecube<float> diffuseEnv [[texture(5)]],
    texturecube<float> specularEnv [[texture(6)]],texture2d<float> ggxLUT [[texture(7)]],
    texturecube<float> charlieEnv [[texture(8)]],texture2d<float> charlieLUT [[texture(9)]],
    texture2d<float> sheenELUT [[texture(10)]],texture2d<float> transmissionBackground [[texture(30)]],
    sampler envSampler [[sampler(5)]]) {
    float4 base=m.baseColor*in.color;
    if(m.flags.x&1u) base*=materialTextures.maps[0].sample(materialTextures.samplers[0],materialUV(in,m,0));
    if(m.flags.y==0) base.a=1;
    // Khronos alpha-tests a lit material only under DEBUG_NONE; unlit always.
    if(m.flags.y==1 && (frame.options.y==0 || (m.flags.z&1u))) { if(base.a<m.surface.w) discard_fragment(); base.a=1; }
    // MATERIAL_UNLIT: TRANSMISSION_PASS writes toneMapInverse(baseColor) with flag 2, else baseColor with flag 1.
    if(m.flags.z&1u) {
        if(frame.options.z&2u) return {float4(toneMapInverse(base.rgb,frame.environment.z,frame.options.x),base.a),2u};
        return {base,1u};
    }
    float metallic=m.surface.x, roughness=m.surface.y;
    if(m.flags.x&2u) { float4 mr=materialTextures.maps[1].sample(materialTextures.samplers[1],materialUV(in,m,1)); metallic*=mr.b; roughness*=mr.g; }
    metallic=clamp(metallic,0.0f,1.0f); roughness=clamp(roughness,0.0f,1.0f);
    float alphaRoughness=roughness*roughness;
    float specularWeight=m.specular.w;
    float3 specularColor=m.specular.rgb;
    float clearcoat=m.coatTransmission.x,coatRoughness=m.coatTransmission.y;
    float3 sheenColor=m.sheen.rgb; float sheenRoughness=m.sheen.w;
    float iridescence=m.volumeIridescence.y, filmThickness=m.volumeIridescence.w;
    float anisotropy=m.anisotropy.x,anisotropyRotation=m.anisotropy.y;
    float transmission=m.coatTransmission.w,thickness=m.volumeIridescence.x;
    float diffuseTransmission=m.anisotropy.z;
    float3 diffuseTransmissionColor=m.diffuseTransmissionColor.rgb;
    if(m.flags.x&(1u<<5)) specularWeight*=materialTextures.maps[5].sample(materialTextures.samplers[5],materialUV(in,m,5)).a;
    if(m.flags.x&(1u<<6)) specularColor*=materialTextures.maps[6].sample(materialTextures.samplers[6],materialUV(in,m,6)).rgb;
    if(m.flags.x&(1u<<7)) clearcoat*=materialTextures.maps[7].sample(materialTextures.samplers[7],materialUV(in,m,7)).r;
    if(m.flags.x&(1u<<8)) coatRoughness*=materialTextures.maps[8].sample(materialTextures.samplers[8],materialUV(in,m,8)).g;
    if(m.flags.x&(1u<<10)) sheenColor*=materialTextures.maps[10].sample(materialTextures.samplers[10],materialUV(in,m,10)).rgb;
    if(m.flags.x&(1u<<11)) sheenRoughness*=materialTextures.maps[11].sample(materialTextures.samplers[11],materialUV(in,m,11)).a;
    if(m.flags.x&(1u<<12)) iridescence*=materialTextures.maps[12].sample(materialTextures.samplers[12],materialUV(in,m,12)).r;
    if(m.flags.x&(1u<<13)) filmThickness=mix(m.extra.x,m.volumeIridescence.w,materialTextures.maps[13].sample(materialTextures.samplers[13],materialUV(in,m,13)).g);
    float2 anisotropyDirection(1,0);
    if(m.flags.x&(1u<<14)) {
        float3 sample=materialTextures.maps[14].sample(materialTextures.samplers[14],materialUV(in,m,14)).rgb;
        anisotropyDirection=sample.xy*2.0f-1.0f; anisotropy*=sample.z;
    }
    if(m.flags.x&(1u<<15)) transmission*=materialTextures.maps[15].sample(materialTextures.samplers[15],materialUV(in,m,15)).r;
    if(m.flags.x&(1u<<16)) thickness*=materialTextures.maps[16].sample(materialTextures.samplers[16],materialUV(in,m,16)).g;
    if(m.flags.x&(1u<<17)) diffuseTransmission*=materialTextures.maps[17].sample(materialTextures.samplers[17],materialUV(in,m,17)).a;
    if(m.flags.x&(1u<<18)) diffuseTransmissionColor*=materialTextures.maps[18].sample(materialTextures.samplers[18],materialUV(in,m,18)).rgb;
    coatRoughness=clamp(coatRoughness,0.0f,1.0f);
    anisotropy=clamp(anisotropy,0.0f,1.0f);
    float3 specGloss=specularColor; float glossiness=m.extra.z;
    if(m.flags.x&(1u<<19)) {
        float4 sg=materialTextures.maps[19].sample(materialTextures.samplers[19],materialUV(in,m,19));
        specGloss*=sg.rgb; glossiness*=sg.a;
    }
    if(m.flags.z&4u) { metallic=0; roughness=1.0f-glossiness; alphaRoughness=roughness*roughness; }
    float3 v=normalize(frame.cameraPosition.xyz-in.worldPosition);
    float3 ng=normalize(in.normal);
    // A zero normal denotes a primitive without authored/generated normals.
    if(dot(in.normal,in.normal)<1e-10f || !all(isfinite(ng))) ng=normalize(cross(dfdx(in.worldPosition),dfdy(in.worldPosition)));
    float3 t=normalize(in.tangent.xyz);
    float3 b=normalize(in.bitangent);
    if(dot(in.tangent.xyz,in.tangent.xyz)<1e-10f || !all(isfinite(t))) {
        // Khronos getNormalInfo without HAS_TANGENT_VEC4: screen-space UV derivatives (GL dFdy
        // is y-up, Metal's y-down), near-zero ones replaced by the unit axes.
        float2 uv=materialUV(in,m,2);
        float2 uvDx=dfdx(uv),uvDy=-dfdy(uv);
        if(length(uvDx)<=1e-2f) uvDx=float2(1,0);
        if(length(uvDy)<=1e-2f) uvDy=float2(0,1);
        float3 tangent=(uvDy.y*dfdx(in.worldPosition)-uvDx.y*-dfdy(in.worldPosition))/(uvDx.x*uvDy.y-uvDy.x*uvDx.y);
        t=normalize(tangent-ng*dot(ng,tangent));
        b=cross(ng,t);
    }
    if(!all(isfinite(b))) b=normalize(cross(ng,t))*in.tangent.w;
    if(!front) { ng=-ng; t=-t; b=-b; }
    float3 n=ng;
    float3 normalTex(0,0,1);
    if(m.flags.x&4u) {
        float3 sample=materialTextures.maps[2].sample(materialTextures.samplers[2],materialUV(in,m,2)).xyz*2.0f-1.0f;
        sample.xy*=m.emissiveNormalScale.w; normalTex=normalize(sample);
        n=normalize(float3x3(t,b,ng)*normalize(sample));
    }
    float nv=clamp(dot(n,v),0.0f,1.0f);
    float ior=m.coatTransmission.z;
    float f0Scalar=(ior-1.0f)/(ior+1.0f); f0Scalar*=f0Scalar;
    float3 f0=(m.flags.z&4u) ? specGloss : min(float3(f0Scalar)*specularColor,float3(1));
    float3 f90=float3(specularWeight);
    float3 dielectricIridescence(0),metalIridescence(0);
    float film=filmThickness>0 ? iridescence : 0;
    if(film>0) {
        dielectricIridescence=evalIridescence(1,m.volumeIridescence.z,nv,filmThickness,f0);
        metalIridescence=evalIridescence(1,m.volumeIridescence.z,nv,filmThickness,base.rgb);
    }
    float3 coatNormal=ng;
    if(m.flags.x&(1u<<9)) {
        float3 sample=materialTextures.maps[9].sample(materialTextures.samplers[9],materialUV(in,m,9)).rgb*2.0f-1.0f;
        sample.xy*=m.extra.w;
        coatNormal=float3x3(t,b,ng)*normalize(sample);
    }
    float3 coatFresnel=F_Schlick(float3(f0Scalar),clamp(dot(coatNormal,v),0.0f,1.0f));
    float3 color(0);
    float c=cos(anisotropyRotation),s=sin(anisotropyRotation);
    float2 ad=float2(c*anisotropyDirection.x-s*anisotropyDirection.y,s*anisotropyDirection.x+c*anisotropyDirection.y);
    float3 anisotropicT=normalize(float3x3(t,b,n)*float3(ad,0)),anisotropicB=cross(ng,anisotropicT);
    if(frame.options.z&1u) {
        float rotation=frame.environment.x,intensity=frame.environment.y,maxLod=frame.environment.w;
        float3 diffuse=diffuseEnv.sample(envSampler,rotateEnvironment(n,rotation)).rgb*intensity*base.rgb;
        if(diffuseTransmission>0) {
            float3 back=diffuseEnv.sample(envSampler,rotateEnvironment(-n,rotation)).rgb*intensity*diffuseTransmissionColor;
            float scale=(length(draw.model[0].xyz)+length(draw.model[1].xyz)+length(draw.model[2].xyz))/3.0f;
            back=applyVolumeAttenuation(back,thickness*scale,m.attenuation.rgb,m.attenuation.w);
            diffuse=mix(diffuse,back,diffuseTransmission);
        }
        if(transmission>0 && !(frame.options.z&2u)) {
            // The page's opaque framebuffer texture: NEAREST magnification (LOD 0 at roughness 0),
            // LINEAR_MIPMAP_LINEAR minification, clamped.
            constexpr sampler transmissionSampler(mag_filter::nearest,min_filter::linear,mip_filter::linear,address::clamp_to_edge);
            float3 transmitted(0); float rayLength=0;
            for(uint channel=0;channel<3;++channel) {
                float halfSpread=(ior-1.0f)*0.025f*m.extra.y;
                float channelIOR=ior+(float(channel)-1.0f)*halfSpread;
                float3 ray=getVolumeTransmissionRay(n,v,thickness,channelIOR,draw.model);
                rayLength=length(ray);
                float4 clip=frame.viewProjection*float4(in.worldPosition+ray,1);
                float2 coord=clip.xy/clip.w*0.5f+0.5f;
                coord.y=1.0f-coord.y;
                float lod=log2(float(transmissionBackground.get_width()))*roughness*clamp(channelIOR*2.0f-2.0f,0.0f,1.0f);
                transmitted[channel]=transmissionBackground.sample(transmissionSampler,coord,level(lod))[channel];
            }
            transmitted=applyVolumeAttenuation(transmitted,rayLength,m.attenuation.rgb,m.attenuation.w)*base.rgb;
            diffuse=mix(diffuse,transmitted,transmission);
        }
        float3 specNormal=anisotropy>0 ? anisotropicBentNormal(n,v,roughness,anisotropy,anisotropicB) : n;
        float3 reflection=normalize(reflect(-v,specNormal));
        float3 specular=specularEnv.sample(envSampler,rotateEnvironment(reflection,rotation),level(roughness*maxLod)).rgb*intensity;
        float2 fab=ggxLUT.sample(envSampler,float2(nv,roughness)).rg;
        float3 fMetal=getIBLGGXFresnel(nv,roughness,base.rgb,1,fab);
        float3 fDielectric=getIBLGGXFresnel(nv,roughness,f0,specularWeight,fab);
        float3 metalBRDF=fMetal*specular,dielectricBRDF=mix(diffuse,specular,fDielectric);
        if(film>0) { metalBRDF=mix(metalBRDF,specular*metalIridescence,film); dielectricBRDF=mix(dielectricBRDF,rgb_mix(diffuse,specular,dielectricIridescence),film); }
        color=mix(dielectricBRDF,metalBRDF,metallic);
        if(any(sheenColor>0)) {
            float sheenBRDF=charlieLUT.sample(envSampler,float2(nv,sheenRoughness)).b;
            float3 sheen=charlieEnv.sample(envSampler,rotateEnvironment(normalize(reflect(-v,n)),rotation),level(sheenRoughness*maxLod)).rgb*intensity*sheenColor*sheenBRDF;
            float scaling=1.0f-max(sheenColor.r,max(sheenColor.g,sheenColor.b))*sheenELUT.sample(envSampler,float2(nv,sheenRoughness)).r;
            color=sheen+color*scaling;
        }
        if(clearcoat>0) {
            float3 coat=specularEnv.sample(envSampler,rotateEnvironment(normalize(reflect(-v,coatNormal)),rotation),level(coatRoughness*maxLod)).rgb*intensity;
            color=mix(color,coat,clearcoat*coatFresnel);
        }
        if(m.flags.x&8u) { float ao=materialTextures.maps[3].sample(materialTextures.samplers[3],materialUV(in,m,3)).r; color*=1.0f+m.surface.z*(ao-1.0f); }
    }
    for(uint i=0;i<frame.options.w;++i) {
        MetalLight light=lights[i];
        float3 pointToLight=uint(light.outerType.y)==0 ? -light.directionRange.xyz : light.positionInnerCone.xyz-in.worldPosition;
        float3 l=normalize(pointToLight),h=normalize(l+v);
        float nl=clamp(dot(n,l),0.0f,1.0f),nh=clamp(dot(n,h),0.0f,1.0f),vh=clamp(dot(v,h),0.0f,1.0f);
        float3 intensity=getLightIntensity(light,pointToLight);
        float3 diffuse=intensity*nl*BRDF_lambertian(base.rgb);
        if(diffuseTransmission>0) {
            diffuse*=1.0f-diffuseTransmission;
            if(dot(n,l)<0) {
                float3 transmitted=intensity*clamp(dot(-n,l),0.0f,1.0f)*BRDF_lambertian(diffuseTransmissionColor);
                float scale=(length(draw.model[0].xyz)+length(draw.model[1].xyz)+length(draw.model[2].xyz))/3.0f;
                diffuse+=applyVolumeAttenuation(transmitted,thickness*scale,m.attenuation.rgb,m.attenuation.w)*diffuseTransmission;
            }
        }
        if(transmission>0) {
            float3 ray=getVolumeTransmissionRay(n,v,thickness,ior,draw.model);
            pointToLight-=ray; l=normalize(pointToLight);
            float3 transmitted=intensity*getPunctualRadianceTransmission(n,v,l,alphaRoughness,base.rgb,ior);
            transmitted=applyVolumeAttenuation(transmitted,length(ray),m.attenuation.rgb,m.attenuation.w);
            diffuse=mix(diffuse,transmitted,transmission);
            intensity=getLightIntensity(light,pointToLight);
        }
        float3 specular=intensity*nl*(anisotropy>0 ? BRDF_specularGGXAnisotropy(alphaRoughness,anisotropy,n,v,l,h,anisotropicT,anisotropicB) : BRDF_specularGGX(alphaRoughness,nl,nv,nh));
        float3 fd=F_Schlick(f0*specularWeight,f90,abs(vh));
        float3 fm=F_Schlick(base.rgb,abs(vh));
        float3 dielectric=mix(diffuse,specular,fd),metal=fm*specular;
        if(film>0) { dielectric=mix(dielectric,rgb_mix(diffuse,specular,dielectricIridescence),film); metal=mix(metal,specular*metalIridescence,film); }
        float3 lightColor=mix(dielectric,metal,metallic);
        if(any(sheenColor>0)) {
            float sheenMax=max(sheenColor.r,max(sheenColor.g,sheenColor.b));
            float eV=sheenELUT.sample(envSampler,float2(nv,sheenRoughness)).r;
            float eL=sheenELUT.sample(envSampler,float2(nl,sheenRoughness)).r;
            float scaling=min(1.0f-sheenMax*eV,1.0f-sheenMax*eL);
            lightColor=intensity*nl*BRDF_specularSheen(sheenColor,sheenRoughness,nl,nv,nh)+lightColor*scaling;
        }
        if(clearcoat>0) {
            float cnl=clamp(dot(coatNormal,l),0.0f,1.0f),cnv=clamp(dot(coatNormal,v),0.0f,1.0f),cnh=clamp(dot(coatNormal,h),0.0f,1.0f);
            float3 coat=intensity*cnl*BRDF_specularGGX(coatRoughness*coatRoughness,cnl,cnv,cnh);
            lightColor=mix(lightColor,coat,clearcoat*coatFresnel);
        }
        color+=lightColor;
    }
    float3 emissive=m.emissiveNormalScale.rgb;
    if(m.flags.x&16u) emissive*=materialTextures.maps[4].sample(materialTextures.samplers[4],materialUV(in,m,4)).rgb;
    color+=emissive*(1.0f-clearcoat*coatFresnel);
    // Stable host-facing channel IDs, mapped to the corresponding Khronos DEBUG outputs. Like
    // Khronos, every channel starts from its grey checkerboard (gl_FragCoord, bottom-left origin)
    // and only overwrites it when the primitive or material has the data; the alpha is 1.
    if(frame.options.y>0) {
        float2 fragCoord=float2(in.position.x,frame.viewport.y-in.position.y);
        float2 v1=step(0.5f,fract(0.02f*fragCoord)),v2=step(0.5f,float2(1.0f)-fract(0.02f*fragCoord));
        color=float3(0.9f+v1.x*v1.y+v2.x*v2.y);
        // flags.w: bit0 TEXCOORD_0, bit1 clearcoat, bit2 specular, bit3 TANGENT, bit4 NORMAL.
        bool hasUV0=m.flags.w&1u,hasClearcoat=m.flags.w&2u,hasSpecular=m.flags.w&4u;
        switch(frame.options.y) {
            case 1: color=linearTosRGB(base.rgb); break;
            case 2: if(m.flags.x&4u) color=(normalTex+1.0f)/2.0f; break;
            case 3: color=float3(metallic); break;
            case 4: color=float3(roughness); break;
            case 5: {
                // No TANGENT attribute: Khronos getNormalInfo's derivative tangent, not the
                // (1,0,0) stand-in packed for the shading TBN. Missing NORMAL uses dFdx×dFdy.
                float3 debugT=t;
                if((m.flags.w&8u)==0u) {
                    float3 basis=ng;
                    if((m.flags.w&16u)==0u) {
                        basis=normalize(cross(dfdx(in.worldPosition),-dfdy(in.worldPosition)));
                        if(!front) basis=-basis;
                    }
                    float2 uv=materialUV(in,m,2);
                    float2 uvDx=dfdx(uv),uvDy=-dfdy(uv);
                    if(length(uvDx)<=1e-2f) uvDx=float2(1,0);
                    if(length(uvDy)<=1e-2f) uvDy=float2(0,1);
                    float3 generated=(uvDy.y*dfdx(in.worldPosition)-uvDx.y*-dfdy(in.worldPosition))/(uvDx.x*uvDy.y-uvDy.x*uvDx.y);
                    debugT=normalize(generated-basis*dot(basis,generated));
                    if(!front) debugT=-debugT;
                }
                color=(debugT+1.0f)/2.0f;
                break;
            }
            case 6: if(hasUV0) color=float3(in.uv0,0); break;
            case 7: if(m.flags.x&8u) color=float3(materialTextures.maps[3].sample(materialTextures.samplers[3],materialUV(in,m,3)).r); break;
            case 8: color=linearTosRGB(emissive); break;
            case 9: color=float3(base.a); break;
            case 10: if(hasSpecular) color=float3(specularWeight); break;
            case 11: if(hasClearcoat) color=float3(clearcoat); break;
            case 12: if(hasClearcoat) color=float3(coatRoughness); break;
            case 13: if(hasClearcoat) color=(coatNormal+float3(1))/2.0f; break;
        }
        return {float4(color,1),0u};
    }
    return {float4(color,base.a),2u};
}
struct FullscreenVaryings { float4 position [[position]]; float2 uv; };
vertex FullscreenVaryings khronos_tonemap_vertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1u)&2u,id&2u);
    return {float4(p*2.0f-1.0f,0,1),float2(p.x,1.0f-p.y)};
}
fragment float4 khronos_tonemap_fragment(FullscreenVaryings in [[stage_in]],
    constant MetalFrameUniforms &frame [[buffer(1)]],texture2d<float> main [[texture(0)]],
    texture2d<uint> flags [[texture(1)]]) {
    uint2 pixel=uint2(in.position.xy);
    float4 color=main.read(pixel);
    uint flag=flags.read(pixel).r;
    // X-ray (options.z bit 8): ghosted parts sit premultiplied over a clear canvas; tone-map
    // their straight colour so the page compositor's divide by alpha does not wash them out.
    bool straight=(frame.options.z&8u) && color.a>0.0001;
    if(straight) color.rgb/=color.a;
    if(flag==1u) color.rgb=linearTosRGB(color.rgb);
    else if(flag==2u) color.rgb=toneMap(color.rgb,frame.environment.z,frame.options.x);
    if(straight) color.rgb*=color.a;
    return color;
}

fragment float4 khronos_present_fragment(FullscreenVaryings in [[stage_in]],texture2d<float> image [[texture(0)]]) {
    constexpr sampler sampling(coord::normalized,address::clamp_to_edge,filter::linear);
    return image.sample(sampling,in.uv);
}

struct LineVertex { float4 position; float4 color; };
struct LineVaryings { float4 position [[position]]; float4 color; };
vertex LineVaryings khronos_line_vertex(uint id [[vertex_id]],device const LineVertex *vertices [[buffer(0)]],constant float4x4 &viewProjection [[buffer(1)]]) {
    float4 clip=viewProjection*vertices[id].position;
    clip.z=(clip.z+clip.w)*0.5f;
    return {clip,vertices[id].color};
}
// Soft depth against the scene's stored depth: the overlay pass is 4× MSAA colour over a
// tonemapped frame, so a hardware depth attachment cannot share sample count with the scene.
// Discard when the line is farther than the model (Metal: larger z is farther).
fragment float4 khronos_line_fragment(LineVaryings in [[stage_in]],
    depth2d<float> sceneDepth [[texture(0)]],constant uint &occlude [[buffer(0)]]) {
    if (occlude != 0u) {
        float scene = sceneDepth.read(uint2(in.position.xy));
        if (in.position.z > scene) discard_fragment();
    }
    return in.color;
}

// Seeds every sample of the overlay MSAA target with the tonemapped frame, as the page's
// tonemap quad fills its antialiased canvas before the overlay lines are drawn.
fragment float4 khronos_overlay_copy_fragment(FullscreenVaryings in [[stage_in]],texture2d<float> image [[texture(0)]]) {
    return image.read(uint2(in.position.xy));
}

// Composites a ~2 px accent ring outside selected mesh IDs (no interior fill).
fragment float4 khronos_selection_outline_fragment(FullscreenVaryings in [[stage_in]],
    texture2d<uint, access::read> ids [[texture(0)]],
    constant float4 &accent [[buffer(0)]]) {
    uint2 p = uint2(in.position.xy);
    uint center = ids.read(p).r;
    if (center != 0u) return float4(0);
    constexpr int radius = 2;
    uint2 size = uint2(ids.get_width(), ids.get_height());
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            if (dx * dx + dy * dy > radius * radius) continue;
            int2 q = int2(p) + int2(dx, dy);
            if (q.x < 0 || q.y < 0 || uint(q.x) >= size.x || uint(q.y) >= size.y) continue;
            if (ids.read(uint2(q)).r != 0u) return accent;
        }
    }
    return float4(0);
}

fragment uint khronos_pick_fragment(MetalVaryings in [[stage_in]],
    constant MetalFrameUniforms &frame [[buffer(1)]],
    constant MetalDrawUniforms &draw [[buffer(2)]],
    constant MetalMaterialUniforms &m [[buffer(3)]],
    constant MaterialTextureArguments &materialTextures [[buffer(5)]],
    constant uint &drawID [[buffer(6)]]) {
    float4 base=m.baseColor*in.color;
    if(m.flags.x&1u) base*=materialTextures.maps[0].sample(materialTextures.samplers[0],materialUV(in,m,0));
    if(m.flags.y==0) base.a=1;
    if(m.flags.y==1 && base.a<m.surface.w) discard_fragment();
    return drawID;
}
