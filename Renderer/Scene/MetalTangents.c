#include "MetalTangents.h"
#include "../../Vendor/mikktspace/mikktspace.h"
#include <math.h>
#include <limits.h>

typedef struct { float *vertices; size_t count; } TangentInput;
static float *vertex(const SMikkTSpaceContext *ctx, int face, int index) {
    TangentInput *input = ctx->m_pUserData;
    return input->vertices + ((size_t)face * 3 + index) * 20;
}
static int faceCount(const SMikkTSpaceContext *ctx) {
    return (int)(((TangentInput *)ctx->m_pUserData)->count / 3);
}
static int faceVertexCount(const SMikkTSpaceContext *ctx, int face) { return 3; }
static void position(const SMikkTSpaceContext *ctx, float out[], int f, int v) {
    const float *p = vertex(ctx,f,v);
    for(int c=0;c<3;++c) out[c]=p[c];
}
static void normal(const SMikkTSpaceContext *ctx, float out[], int f, int v) {
    const float *p = vertex(ctx,f,v)+4;
    const float length = sqrtf(p[0]*p[0]+p[1]*p[1]+p[2]*p[2]);
    for(int c=0;c<3;++c) out[c]=length > 0 ? p[c]/length : (c==2 ? 1 : 0);
}
static void texcoord(const SMikkTSpaceContext *ctx, float out[], int f, int v) {
    const float *p=vertex(ctx,f,v)+16; out[0]=p[0]; out[1]=p[1];
}
static void tangent(const SMikkTSpaceContext *ctx, const float direction[], float sign, int f, int v) {
    float *p=vertex(ctx,f,v)+8;
    for(int c=0;c<3;++c) p[c]=direction[c];
    // Khronos flips MikkTSpace's w after generation ("convert coordinate system handedness").
    p[3]=-sign;
}
bool GLTFMetalGenerateTangents(void *vertices, size_t count) {
    if(!vertices || count < 3 || count % 3 || count/3 > INT_MAX) return false;
    TangentInput input={vertices,count};
    SMikkTSpaceInterface callbacks={faceCount,faceVertexCount,position,normal,texcoord,tangent,0};
    SMikkTSpaceContext ctx={&callbacks,&input};
    return genTangSpaceDefault(&ctx) != 0;
}
