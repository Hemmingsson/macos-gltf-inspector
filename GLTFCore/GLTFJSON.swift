import Foundation
import simd

/// Typed reads of `JSONSerialization` values for the glTF JSON readers.
enum GLTFJSON {
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let n as Int: return n
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let n as Double: return n
        case let n as Int: return Double(n)
        default: return nil
        }
    }

    /// Non-numeric elements read as 0.
    static func doubles(_ value: Any?) -> [Double]? {
        guard let value else { return nil }
        if let typed = value as? [Double] { return typed }
        guard let array = value as? NSArray else { return nil }
        var values: [Double] = []
        values.reserveCapacity(array.count)
        for element in array {
            values.append(double(element) ?? 0)
        }
        return values
    }

    /// Non-integer elements are dropped.
    static func ints(_ value: Any?) -> [Int] {
        guard let value else { return [] }
        if let typed = value as? [Int] { return typed }
        guard let array = value as? NSArray else { return [] }
        var values: [Int] = []
        values.reserveCapacity(array.count)
        for element in array {
            if let n = int(element) { values.append(n) }
        }
        return values
    }

    static func float(_ value: Any?) -> Float? {
        double(value).map(Float.init)
    }

    static func float3(_ value: Any?) -> SIMD3<Float>? {
        guard let array = value as? NSArray, array.count >= 3 else { return nil }
        return SIMD3<Float>(floatAt(0, in: array), floatAt(1, in: array), floatAt(2, in: array))
    }

    static func float4(_ value: Any?) -> SIMD4<Float>? {
        guard let array = value as? NSArray, array.count >= 4 else { return nil }
        return SIMD4<Float>(
            floatAt(0, in: array),
            floatAt(1, in: array),
            floatAt(2, in: array),
            floatAt(3, in: array)
        )
    }

    /// Column-major 4×4 from a 16-number array. Nil when the value is missing or the wrong length.
    static func float4x4(_ value: Any?) -> simd_float4x4? {
        guard let array = value as? NSArray, array.count == 16 else { return nil }
        return simd_float4x4(
            SIMD4<Float>(floatAt(0, in: array), floatAt(1, in: array), floatAt(2, in: array), floatAt(3, in: array)),
            SIMD4<Float>(floatAt(4, in: array), floatAt(5, in: array), floatAt(6, in: array), floatAt(7, in: array)),
            SIMD4<Float>(floatAt(8, in: array), floatAt(9, in: array), floatAt(10, in: array), floatAt(11, in: array)),
            SIMD4<Float>(floatAt(12, in: array), floatAt(13, in: array), floatAt(14, in: array), floatAt(15, in: array))
        )
    }

    private static func floatAt(_ index: Int, in array: NSArray) -> Float {
        Float((array[index] as? NSNumber)?.doubleValue ?? 0)
    }

    /// `count` of the accessor `value` indexes; 0 when it is missing.
    static func accessorCount(_ value: Any?, accessors: [[String: Any]]) -> Int {
        guard let index = int(value), accessors.indices.contains(index) else { return 0 }
        return int(accessors[index]["count"]) ?? 0
    }

    /// Triangles one primitive draws: lists `count / 3`, strips and fans `count - 2`, other
    /// modes none. `count` is the indices, or the positions when unindexed.
    static func triangleCount(_ primitive: [String: Any], accessors: [[String: Any]]) -> Int {
        let attributes = primitive["attributes"] as? [String: Any] ?? [:]
        let count = accessorCount(primitive["indices"] ?? attributes["POSITION"], accessors: accessors)
        switch int(primitive["mode"]) ?? 4 {
        case 4: return count / 3
        case 5, 6: return max(0, count - 2)
        default: return 0
        }
    }
}
