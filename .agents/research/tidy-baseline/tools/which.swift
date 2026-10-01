import AppKit
for p in CommandLine.arguments.dropFirst() {
    let u = URL(fileURLWithPath: p)
    print(p.split(separator: "/").last!, "->", NSWorkspace.shared.urlForApplication(toOpen: u)?.path ?? "none")
}
