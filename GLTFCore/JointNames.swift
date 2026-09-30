/// Joint names shared by the JSON document and every renderer, so a skin's joints read the same
/// in the sidebar, the skeleton overlay and animation bind paths.
public enum JointNames {
    public static func synthesized(index: Int) -> String {
        "joint-\(index)"
    }

    public static func resolved(_ raw: String?, index: Int) -> String {
        let name = raw ?? ""
        return name.isEmpty ? synthesized(index: index) : name
    }
}
