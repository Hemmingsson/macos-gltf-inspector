#ifndef MetalTangents_h
#define MetalTangents_h
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/// Vertices are deindexed triangles with the 80-byte MetalVertex layout.
bool GLTFMetalGenerateTangents(void *vertices, size_t vertexCount);
#ifdef __cplusplus
}
#endif
#endif
