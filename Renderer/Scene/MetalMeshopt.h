#ifndef MetalMeshopt_h
#define MetalMeshopt_h
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/// Decodes one EXT_/KHR_meshopt_compression bufferView with the official meshoptimizer decoder.
/// mode: 0 ATTRIBUTES, 1 TRIANGLES, 2 INDICES. filter: 0 NONE, 1 OCTAHEDRAL, 2 QUATERNION,
/// 3 EXPONENTIAL, 4 COLOR. `destination` holds count * stride bytes.
bool GLTFMetalMeshoptDecode(void *destination, size_t count, size_t stride,
                            const uint8_t *source, size_t sourceLength, int mode, int filter);
#ifdef __cplusplus
}
#endif
#endif
