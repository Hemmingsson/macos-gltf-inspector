import GLTFCore
import GLTFKit2

enum Skin {
    static func resolvedName(_ raw: String?, index: Int) -> String {
        JointNames.resolved(raw, index: index)
    }

    static func jointIndex(of node: GLTFNode, in skins: [GLTFSkin]) -> Int? {
        for skin in skins {
            if let index = skin.joints.firstIndex(of: node) {
                return index
            }
        }
        return nil
    }
}
