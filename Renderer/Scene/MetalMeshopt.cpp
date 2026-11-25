#include "MetalMeshopt.h"
#include "../../Vendor/meshoptimizer/meshoptimizer.h"

bool GLTFMetalMeshoptDecode(void *destination, size_t count, size_t stride,
                            const uint8_t *source, size_t sourceLength, int mode, int filter) {
    int result = -1;
    switch (mode) {
    case 0: result = meshopt_decodeVertexBuffer(destination, count, stride, source, sourceLength); break;
    case 1: result = meshopt_decodeIndexBuffer(destination, count, stride, source, sourceLength); break;
    case 2: result = meshopt_decodeIndexSequence(destination, count, stride, source, sourceLength); break;
    default: return false;
    }
    if (result != 0) return false;
    if (mode != 0) return filter == 0;
    switch (filter) {
    case 0: break;
    case 1: if (stride != 4 && stride != 8) return false; meshopt_decodeFilterOct(destination, count, stride); break;
    case 2: if (stride != 8) return false; meshopt_decodeFilterQuat(destination, count, stride); break;
    case 3: if (stride % 4 != 0) return false; meshopt_decodeFilterExp(destination, count, stride); break;
    case 4: if (stride != 4 && stride != 8) return false; meshopt_decodeFilterColor(destination, count, stride); break;
    default: return false;
    }
    return true;
}
