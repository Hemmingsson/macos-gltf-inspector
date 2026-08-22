import Foundation
import GLTFKit2
import simd

enum Packed {
    static func floatData(for accessor: GLTFAccessor) -> Data? {
        let packed = GLTFPackedDataForAccessor(accessor)
        guard packed.count > 0 else { return nil }
        if accessor.componentType == .float {
            return packed
        }
        return GLTFTransformPackedDataToFloat(packed, accessor)
    }

    static func floatArray(for accessor: GLTFAccessor) -> [Float]? {
        packedFloats(accessor, dimension: 1, allowed: { $0 == .scalar }) { src, count in
            Array(src.prefix(count))
        }
    }

    static func isTightFloat(_ accessor: GLTFAccessor, dimension: GLTFValueDimension) -> Bool {
        guard accessor.sparse == nil,
              accessor.componentType == .float,
              !accessor.isNormalized,
              accessor.dimension == dimension,
              let bufferView = accessor.bufferView,
              bufferView.meshoptCompression == nil,
              bufferView.buffer.data != nil
        else { return false }
        let elementSize = MemoryLayout<Float>.size * {
            switch dimension {
            case .vector2: return 2
            case .vector3: return 3
            case .vector4: return 4
            default: return 0
            }
        }()
        guard elementSize > 0 else { return false }
        let stride = bufferView.stride
        return stride == 0 || stride == elementSize
    }

    static func copyTight(_ accessor: GLTFAccessor, elementFloats: Int, to dest: UnsafeMutableRawPointer) {
        guard let bufferView = accessor.bufferView,
              let data = bufferView.buffer.data
        else { return }
        let byteCount = accessor.count * elementFloats * MemoryLayout<Float>.size
        let offset = bufferView.offset + accessor.offset
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, offset + byteCount <= raw.count else { return }
            memcpy(dest, base + offset, byteCount)
        }
    }

    static func float2Array(for accessor: GLTFAccessor, flipVertically: Bool = false) -> [SIMD2<Float>]? {
        packedFloats(accessor, dimension: 2, allowed: { $0 == .vector2 }) { src, count in
            [SIMD2<Float>](unsafeUninitializedCapacity: count) { dest, initializedCount in
                for i in 0..<count {
                    let y = src[i * 2 + 1]
                    dest[i] = SIMD2(src[i * 2], flipVertically ? 1 - y : y)
                }
                initializedCount = count
            }
        }
    }

    static func float3Array(for accessor: GLTFAccessor) -> [SIMD3<Float>]? {
        if accessor.dimension == .vector4 {
            return float4Array(for: accessor)?.map { SIMD3($0.x, $0.y, $0.z) }
        }
        return packedFloats(accessor, dimension: 3, allowed: { $0 == .vector3 }) { src, count in
            [SIMD3<Float>](unsafeUninitializedCapacity: count) { dest, initializedCount in
                for i in 0..<count {
                    dest[i] = SIMD3(src[i * 3], src[i * 3 + 1], src[i * 3 + 2])
                }
                initializedCount = count
            }
        }
    }

    static func float4Array(for accessor: GLTFAccessor) -> [SIMD4<Float>]? {
        packedFloats(accessor, dimension: 4, allowed: { $0 == .vector4 }) { src, count in
            [SIMD4<Float>](unsafeUninitializedCapacity: count) { dest, initializedCount in
                for i in 0..<count {
                    dest[i] = SIMD4(src[i * 4], src[i * 4 + 1], src[i * 4 + 2], src[i * 4 + 3])
                }
                initializedCount = count
            }
        }
    }

    /// glTF `COLOR_*` is VEC3 or VEC4; RealityKit mesh colors are always RGBA.
    static func color4Array(for accessor: GLTFAccessor) -> [SIMD4<Float>]? {
        switch accessor.dimension {
        case .vector3:
            return float3Array(for: accessor)?.map { SIMD4($0.x, $0.y, $0.z, 1) }
        case .vector4:
            return float4Array(for: accessor)
        default:
            return nil
        }
    }

    static func quatfArray(for accessor: GLTFAccessor) -> [simd_quatf]? {
        float4Array(for: accessor)?.map { simd_quaternion($0.x, $0.y, $0.z, $0.w) }
    }

    static func uint32Array(for accessor: GLTFAccessor) -> [UInt32]? {
        guard let bufferView = accessor.bufferView, let bufferData = bufferView.buffer.data else { return nil }
        let indexCount = accessor.count
        let offset = bufferView.offset + accessor.offset
        return [UInt32](unsafeUninitializedCapacity: indexCount) { buffer, initializedCount in
            bufferData.withUnsafeBytes { rawPtr in
                switch accessor.componentType {
                case .unsignedByte:
                    guard let src = rawPtr.baseAddress?.advanced(by: offset)
                        .bindMemory(to: UInt8.self, capacity: indexCount)
                    else { initializedCount = 0; return }
                    for i in 0..<indexCount { buffer[i] = UInt32(src[i]) }
                    initializedCount = indexCount
                case .unsignedShort:
                    guard let src = rawPtr.baseAddress?.advanced(by: offset)
                        .bindMemory(to: UInt16.self, capacity: indexCount)
                    else { initializedCount = 0; return }
                    for i in 0..<indexCount { buffer[i] = UInt32(src[i]) }
                    initializedCount = indexCount
                case .unsignedInt:
                    guard let src = rawPtr.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
                    memcpy(UnsafeMutableRawPointer(buffer.baseAddress!), src, MemoryLayout<UInt32>.stride * indexCount)
                    initializedCount = indexCount
                default:
                    initializedCount = 0
                }
            }
        }
    }

    static func ushort4Array(for accessor: GLTFAccessor) -> [SIMD4<UInt16>]? {
        if (accessor.componentType != .unsignedByte && accessor.componentType != .unsignedShort)
            || accessor.dimension != .vector4
        {
            return nil
        }
        guard let bufferView = accessor.bufferView, let bufferData = bufferView.buffer.data else { return nil }
        let vectorCount = accessor.count
        let offset = bufferView.offset + accessor.offset
        return [SIMD4<UInt16>](unsafeUninitializedCapacity: vectorCount) { destPtr, initializedCount in
            bufferData.withUnsafeBytes { sourcePtr in
                initializedCount = 0
                guard let accessorBase = sourcePtr.baseAddress?.advanced(by: offset) else { return }
                switch accessor.componentType {
                case .unsignedByte:
                    let sourceStride = bufferView.stride == 0 ? MemoryLayout<SIMD4<UInt8>>.stride : bufferView.stride
                    for i in 0..<vectorCount {
                        let components = accessorBase.advanced(by: sourceStride * i).bindMemory(to: UInt8.self, capacity: 4)
                        destPtr[i] = SIMD4(
                            UInt16(components[0]),
                            UInt16(components[1]),
                            UInt16(components[2]),
                            UInt16(components[3])
                        )
                    }
                    initializedCount = vectorCount
                case .unsignedShort:
                    let sourceStride = bufferView.stride == 0 ? MemoryLayout<SIMD4<UInt16>>.stride : bufferView.stride
                    if sourceStride == MemoryLayout<SIMD4<UInt16>>.stride {
                        memcpy(UnsafeMutableRawPointer(destPtr.baseAddress!), accessorBase, sourceStride * vectorCount)
                    } else {
                        for i in 0..<vectorCount {
                            let components = accessorBase.advanced(by: sourceStride * i)
                                .bindMemory(to: UInt16.self, capacity: 4)
                            destPtr[i] = SIMD4(components[0], components[1], components[2], components[3])
                        }
                    }
                    initializedCount = vectorCount
                default:
                    break
                }
            }
        }
    }

    static func float4x4(for accessor: GLTFAccessor) -> [simd_float4x4]? {
        if accessor.componentType != .float || accessor.dimension != .matrix4 { return nil }
        guard let bufferView = accessor.bufferView, let bufferData = bufferView.buffer.data else { return nil }
        let sourceStride = bufferView.stride == 0 ? MemoryLayout<simd_float4x4>.stride : bufferView.stride
        let offset = bufferView.offset + accessor.offset
        return [simd_float4x4](unsafeUninitializedCapacity: accessor.count) { destPtr, initializedCount in
            bufferData.withUnsafeBytes { sourceBase in
                guard let accessorBase = sourceBase.baseAddress?.advanced(by: offset) else {
                    initializedCount = 0
                    return
                }
                if sourceStride == MemoryLayout<simd_float4x4>.stride {
                    memcpy(&destPtr[0], accessorBase, sourceStride * accessor.count)
                } else {
                    for i in 0..<accessor.count {
                        memcpy(&destPtr[i], accessorBase.advanced(by: sourceStride * i), MemoryLayout<simd_float4x4>.size)
                    }
                }
                initializedCount = accessor.count
            }
        }
    }

    private static func packedFloats<T>(
        _ accessor: GLTFAccessor,
        dimension: Int,
        allowed: (GLTFValueDimension) -> Bool,
        build: (UnsafeBufferPointer<Float>, Int) -> [T]
    ) -> [T]? {
        guard allowed(accessor.dimension), let data = floatData(for: accessor) else { return nil }
        let count = accessor.count
        guard data.count >= count * dimension * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { rawPtr in
            build(rawPtr.bindMemory(to: Float.self), count)
        }
    }
}
