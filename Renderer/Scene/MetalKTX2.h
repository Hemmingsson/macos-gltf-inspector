#ifndef MetalKTX2_h
#define MetalKTX2_h
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct GLTFMetalKTX2 GLTFMetalKTX2;
/// Parses a KTX2 image. Basis Universal payloads (ETC1S and UASTC) are transcoded to ASTC 4x4,
/// the first choice of the pinned Khronos viewer's KtxDecoder. Returns NULL on failure.
GLTFMetalKTX2 *GLTFMetalKTX2Create(const void *bytes, size_t length);
void GLTFMetalKTX2Destroy(GLTFMetalKTX2 *texture);
/// Vulkan format after transcoding (ASTC 4x4 is 157 unorm / 158 sRGB).
uint32_t GLTFMetalKTX2VkFormat(const GLTFMetalKTX2 *texture);
uint32_t GLTFMetalKTX2Width(const GLTFMetalKTX2 *texture);
uint32_t GLTFMetalKTX2Height(const GLTFMetalKTX2 *texture);
uint32_t GLTFMetalKTX2LevelCount(const GLTFMetalKTX2 *texture);
/// True when the data format descriptor declares an sRGB transfer function.
bool GLTFMetalKTX2IsSRGB(const GLTFMetalKTX2 *texture);
const void *GLTFMetalKTX2Level(const GLTFMetalKTX2 *texture, uint32_t level, size_t *bytesPerRow, size_t *bytesPerImage);
#ifdef __cplusplus
}
#endif
#endif
