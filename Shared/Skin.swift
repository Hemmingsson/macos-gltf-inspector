import GLTFKit2

enum Skin {
    static func synthesizedName(index: Int) -> String {
        "joint-\(index)"
    }

    static func resolvedName(_ raw: String?, index: Int) -> String {
        let name = raw ?? ""
        return name.isEmpty ? synthesizedName(index: index) : name
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
