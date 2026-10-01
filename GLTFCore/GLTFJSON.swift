import Foundation

/// Typed reads of `JSONSerialization` values for the glTF JSON readers.
enum GLTFJSON {
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    /// Non-numeric elements read as 0.
    static func doubles(_ value: Any?) -> [Double]? {
        (value as? [Any])?.map { double($0) ?? 0 }
    }

    /// Non-integer elements are dropped.
    static func ints(_ value: Any?) -> [Int] {
        (value as? [Any])?.compactMap { int($0) } ?? []
    }

    static func float(_ value: Any?) -> Float? {
        double(value).map(Float.init)
    }

    static func float3(_ value: Any?) -> SIMD3<Float>? {
        guard let values = doubles(value), values.count >= 3 else { return nil }
        return SIMD3<Float>(Float(values[0]), Float(values[1]), Float(values[2]))
    }

    static func float4(_ value: Any?) -> SIMD4<Float>? {
        guard let values = doubles(value), values.count >= 4 else { return nil }
        return SIMD4<Float>(Float(values[0]), Float(values[1]), Float(values[2]), Float(values[3]))
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
