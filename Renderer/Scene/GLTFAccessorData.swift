import Foundation
import GLTFKit2

enum GLTFAccessorDataError: Error {
    case invalidRange
}

enum GLTFAccessorData {
    static func packed(_ accessor: GLTFAccessor) throws -> Data {
        guard let elementSize = elementSize(accessor), isInBounds(accessor, elementSize: elementSize) else {
            throw GLTFAccessorDataError.invalidRange
        }
        if let sparse = accessor.sparse, !sparseIndicesFit(sparse, accessorCount: accessor.count) {
            throw GLTFAccessorDataError.invalidRange
        }
        return GLTFPackedDataForAccessor(accessor)
    }

    private static func elementSize(_ accessor: GLTFAccessor) -> Int? {
        let bytes = Int(GLTFBytesPerComponentForComponentType(accessor.componentType))
        let components = Int(GLTFComponentCountForDimension(accessor.dimension))
        guard bytes > 0, components > 0 else { return nil }
        let (size, overflow) = bytes.multipliedReportingOverflow(by: components)
        return overflow ? nil : size
    }

    private static func isInBounds(_ accessor: GLTFAccessor, elementSize: Int) -> Bool {
        guard accessor.count >= 0 else { return false }
        let (packedSize, allocationOverflow) = accessor.count.multipliedReportingOverflow(by: elementSize)
        guard !allocationOverflow else { return false }
        if let view = accessor.bufferView {
            guard viewFits(view) else { return false }
            let stride = view.stride == 0 ? elementSize : view.stride
            guard rangeFits(offset: accessor.offset, count: accessor.count, stride: stride,
                            elementSize: elementSize, length: view.length) else { return false }
        } else if accessor.offset != 0, accessor.sparse == nil {
            return false
        }
        guard let sparse = accessor.sparse else { return true }
        guard sparse.count >= 0, sparse.count <= accessor.count,
              viewFits(sparse.indices), viewFits(sparse.values) else { return false }
        switch sparse.indexComponentType {
        case .unsignedByte, .unsignedShort, .unsignedInt: break
        default: return false
        }
        let indexSize = Int(GLTFBytesPerComponentForComponentType(sparse.indexComponentType))
        guard [1, 2, 4].contains(indexSize),
              rangeFits(offset: sparse.indexOffset, count: sparse.count, stride: indexSize,
                        elementSize: indexSize, length: sparse.indices.length) else { return false }
        let valueStride = sparse.values.stride == 0 ? elementSize : sparse.values.stride
        return rangeFits(offset: sparse.valueOffset, count: sparse.count, stride: valueStride,
                         elementSize: elementSize, length: sparse.values.length) && packedSize >= 0
    }

    private static func sparseIndicesFit(_ sparse: GLTFSparseStorage, accessorCount: Int) -> Bool {
        guard let data = sparse.indices.buffer.data else { return false }
        let size = Int(GLTFBytesPerComponentForComponentType(sparse.indexComponentType))
        for index in 0..<sparse.count {
            let (delta, mulOverflow) = index.multipliedReportingOverflow(by: size)
            let (relative, addOverflow) = sparse.indexOffset.addingReportingOverflow(delta)
            let (offset, viewOverflow) = sparse.indices.offset.addingReportingOverflow(relative)
            guard !mulOverflow, !addOverflow, !viewOverflow else { return false }
            let value: UInt32
            switch size {
            case 1: value = UInt32(data[offset])
            case 2: value = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            case 4: value = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            default: return false
            }
            guard UInt64(value) < UInt64(accessorCount) else { return false }
        }
        return true
    }

    private static func viewFits(_ view: GLTFBufferView) -> Bool {
        guard let data = view.buffer.data, view.offset >= 0, view.length >= 0 else { return false }
        let (end, overflow) = view.offset.addingReportingOverflow(view.length)
        return !overflow && end <= data.count
    }

    private static func rangeFits(offset: Int, count: Int, stride: Int, elementSize: Int, length: Int) -> Bool {
        guard offset >= 0, count >= 0, stride >= elementSize, elementSize > 0, length >= 0 else { return false }
        guard count > 0 else { return offset <= length }
        let (preceding, strideOverflow) = (count - 1).multipliedReportingOverflow(by: stride)
        let (last, offsetOverflow) = offset.addingReportingOverflow(preceding)
        let (end, endOverflow) = last.addingReportingOverflow(elementSize)
        return !strideOverflow && !offsetOverflow && !endOverflow && end <= length
    }
}
