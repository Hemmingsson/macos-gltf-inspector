#include "MetalKTX2.h"
#include <ktx.h>
#include <stdlib.h>

struct GLTFMetalKTX2 { ktxTexture2 *ktx; };

GLTFMetalKTX2 *GLTFMetalKTX2Create(const void *bytes, size_t length) {
    ktxTexture2 *ktx = NULL;
    ktx_uint32_t flags = KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT | KTX_TEXTURE_CREATE_SKIP_KVDATA_BIT;
    if (ktxTexture2_CreateFromMemory(bytes, length, flags, &ktx) != KTX_SUCCESS) return NULL;
    if (ktxTexture2_NeedsTranscoding(ktx) &&
        ktxTexture2_TranscodeBasis(ktx, KTX_TTF_ASTC_4x4_RGBA, 0) != KTX_SUCCESS) {
        ktxTexture_Destroy((ktxTexture *)ktx);
        return NULL;
    }
    if (ktx->numDimensions != 2 || ktx->numFaces != 1 || ktx->numLayers != 1 || ktx->numLevels == 0) {
        ktxTexture_Destroy((ktxTexture *)ktx);
        return NULL;
    }
    GLTFMetalKTX2 *out = malloc(sizeof *out);
    if (!out) { ktxTexture_Destroy((ktxTexture *)ktx); return NULL; }
    out->ktx = ktx;
    return out;
}

void GLTFMetalKTX2Destroy(GLTFMetalKTX2 *texture) {
    if (!texture) return;
    ktxTexture_Destroy((ktxTexture *)texture->ktx);
    free(texture);
}

uint32_t GLTFMetalKTX2VkFormat(const GLTFMetalKTX2 *t) { return t->ktx->vkFormat; }
uint32_t GLTFMetalKTX2Width(const GLTFMetalKTX2 *t) { return t->ktx->baseWidth; }
uint32_t GLTFMetalKTX2Height(const GLTFMetalKTX2 *t) { return t->ktx->baseHeight; }
uint32_t GLTFMetalKTX2LevelCount(const GLTFMetalKTX2 *t) { return t->ktx->numLevels; }
bool GLTFMetalKTX2IsSRGB(const GLTFMetalKTX2 *t) { return ktxTexture2_GetOETF_e(t->ktx) == KHR_DF_TRANSFER_SRGB; }

const void *GLTFMetalKTX2Level(const GLTFMetalKTX2 *t, uint32_t level, size_t *bytesPerRow, size_t *bytesPerImage) {
    ktxTexture *base = (ktxTexture *)t->ktx;
    ktx_size_t offset = 0;
    if (level >= t->ktx->numLevels || ktxTexture_GetImageOffset(base, level, 0, 0, &offset) != KTX_SUCCESS) return NULL;
    if (bytesPerRow) *bytesPerRow = ktxTexture_GetRowPitch(base, level);
    if (bytesPerImage) *bytesPerImage = ktxTexture_GetImageSize(base, level);
    return ktxTexture_GetData(base) + offset;
}
