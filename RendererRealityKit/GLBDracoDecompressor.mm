#import "GLBDracoDecompressor.h"

#include <draco/compression/decode.h>

static GLTFComponentType GLTFComponentTypeForDracoDataType(draco::DataType type) {
    switch (type) {
    case draco::DT_INT8:
        return GLTFComponentTypeByte;
    case draco::DT_UINT8:
        return GLTFComponentTypeUnsignedByte;
    case draco::DT_INT16:
        return GLTFComponentTypeShort;
    case draco::DT_UINT16:
        return GLTFComponentTypeUnsignedShort;
    case draco::DT_UINT32:
        return GLTFComponentTypeUnsignedInt;
    case draco::DT_FLOAT32:
        return GLTFComponentTypeFloat;
    default:
        return GLTFComponentTypeInvalid;
    }
}

static void *GLTFCopyPointAttributeData(const draco::PointCloud &pc, const draco::PointAttribute &pa, int &outSize) {
    int pointCount = pc.num_points();
    draco::DataType type = pa.data_type();
    int componentCount = pa.num_components();
    int componentSize = draco::DataTypeLength(type);
    int elementSize = componentCount * componentSize;
    int dataSize = pointCount * elementSize;
    void *data = malloc(dataSize);
    if (pa.is_mapping_identity()) {
        auto attrPtr = pa.GetAddress(draco::AttributeValueIndex(0));
        ::memcpy(data, attrPtr, dataSize);
    } else {
        for (draco::PointIndex i(0); i < pointCount; ++i) {
            const draco::AttributeValueIndex valueIndex = pa.mapped_index(i);
            void *elementPtr = (char *)data + i.value() * elementSize;
            pa.GetValue(valueIndex, elementPtr);
        }
    }
    outSize = dataSize;
    return data;
}

static uint32_t *GLTFCopyUInt32IndexDataForMesh(draco::Mesh *mesh, size_t &outIndexCount, size_t &outIndexBufferSize) {
    size_t indexCount = mesh->num_faces() * 3;
    size_t indexBufferSize = indexCount * sizeof(uint32_t);
    uint32_t *indices = (uint32_t *)calloc(indexCount, sizeof(uint32_t));
    for (int f = 0; f < mesh->num_faces(); ++f) {
        auto const &face = mesh->face(draco::FaceIndex(f));
        indices[f * 3 + 0] = face[0].value();
        indices[f * 3 + 1] = face[1].value();
        indices[f * 3 + 2] = face[2].value();
    }
    outIndexCount = indexCount;
    outIndexBufferSize = indexBufferSize;
    return indices;
}

@implementation GLBDracoDecompressor

+ (GLTFPrimitive *)newPrimitiveForCompressedBufferView:(GLTFBufferView *)bufferView
                                          attributeMap:(NSDictionary<NSString *, NSNumber *> *)attributeMap
{
    NSData *bufferData = bufferView.buffer.data;
    if (bufferData == nil || bufferView.length <= 0) {
        NSLog(@"[GLTFInspector][draco] skip empty bufferView length=%ld", (long)bufferView.length);
        return nil;
    }
    if (bufferView.offset < 0 || (NSUInteger)(bufferView.offset + bufferView.length) > bufferData.length) {
        NSLog(@"[GLTFInspector][draco] skip OOB offset=%ld length=%ld buffer=%lu",
              (long)bufferView.offset, (long)bufferView.length, (unsigned long)bufferData.length);
        return nil;
    }

    const char *data = (const char *)bufferData.bytes + bufferView.offset;
    draco::DecoderBuffer buffer;
    buffer.Init(data, (size_t)bufferView.length);
    draco::Decoder decoder;
    auto typeOrStatus = draco::Decoder::GetEncodedGeometryType(&buffer);
    if (!typeOrStatus.ok()) {
        NSLog(@"[GLTFInspector][draco] GetEncodedGeometryType failed");
        return nil;
    }
    if (typeOrStatus.value() != draco::TRIANGULAR_MESH) {
        NSLog(@"[GLTFInspector][draco] not a triangular mesh type=%d", (int)typeOrStatus.value());
        return nil;
    }

    auto meshOrStatus = decoder.DecodeMeshFromBuffer(&buffer);
    if (!meshOrStatus.ok()) {
        NSLog(@"[GLTFInspector][draco] DecodeMeshFromBuffer failed");
        return nil;
    }
    std::unique_ptr<draco::Mesh> mesh = std::move(meshOrStatus).value();
    draco::Mesh *meshPtr = mesh.get();
    NSLog(@"[GLTFInspector][draco] decoded points=%d faces=%d attributes=%lu bytes=%ld",
          meshPtr->num_points(), meshPtr->num_faces(),
          (unsigned long)attributeMap.count, (long)bufferView.length);

    NSMutableArray<GLTFAttribute *> *attributes = [NSMutableArray array];
    [attributeMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *index, BOOL *stop) {
        uint32_t attrId = index.unsignedIntValue;
        const draco::PointAttribute *dracoAttribute = meshPtr->GetAttributeByUniqueId(attrId);
        if (dracoAttribute == nullptr) {
            return;
        }
        int attributeBufferLength = 0;
        void *attributePtr = GLTFCopyPointAttributeData(*meshPtr, *dracoAttribute, attributeBufferLength);
        NSData *attributeData = [NSData dataWithBytesNoCopy:attributePtr
                                                     length:(NSUInteger)attributeBufferLength
                                               freeWhenDone:YES];
        GLTFBuffer *attributeBuffer = [[GLTFBuffer alloc] initWithData:attributeData];
        GLTFBufferView *attributeBufferView = [[GLTFBufferView alloc] initWithBuffer:attributeBuffer
                                                                              length:attributeBufferLength
                                                                              offset:0
                                                                              stride:0];
        GLTFComponentType componentType = GLTFComponentTypeForDracoDataType(dracoAttribute->data_type());
        GLTFValueDimension dimension = static_cast<GLTFValueDimension>(dracoAttribute->num_components());
        BOOL normalized = dracoAttribute->normalized();
        GLTFAccessor *attributeAccessor = [[GLTFAccessor alloc] initWithBufferView:attributeBufferView
                                                                            offset:0
                                                                     componentType:componentType
                                                                         dimension:dimension
                                                                             count:meshPtr->num_points()
                                                                        normalized:normalized];
        GLTFAttribute *attribute = [[GLTFAttribute alloc] initWithName:key accessor:attributeAccessor];
        [attributes addObject:attribute];
    }];

    size_t indexCount = 0;
    size_t indexBufferSize = 0;
    uint32_t *indices = GLTFCopyUInt32IndexDataForMesh(meshPtr, indexCount, indexBufferSize);
    NSData *indexData = [NSData dataWithBytesNoCopy:indices length:indexBufferSize freeWhenDone:YES];
    GLTFBuffer *indexBuffer = [[GLTFBuffer alloc] initWithData:indexData];
    GLTFBufferView *indexBufferView = [[GLTFBufferView alloc] initWithBuffer:indexBuffer
                                                                      length:(NSInteger)indexBufferSize
                                                                      offset:0
                                                                      stride:0];
    GLTFAccessor *indexAccessor = [[GLTFAccessor alloc] initWithBufferView:indexBufferView
                                                                    offset:0
                                                             componentType:GLTFComponentTypeUnsignedInt
                                                                 dimension:GLTFValueDimensionScalar
                                                                     count:(NSInteger)indexCount
                                                                normalized:NO];

    return [[GLTFPrimitive alloc] initWithPrimitiveType:GLTFPrimitiveTypeTriangles
                                             attributes:attributes
                                                indices:indexAccessor];
}

@end
