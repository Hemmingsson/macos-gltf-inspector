import AppKit
import QuickLookThumbnailing
let u = URL(fileURLWithPath: CommandLine.arguments[1])
let r = QLThumbnailGenerator.Request(fileAt: u, size: CGSize(width: 256, height: 256), scale: 2, representationTypes: .thumbnail)
let sem = DispatchSemaphore(value: 0)
QLThumbnailGenerator.shared.generateBestRepresentation(for: r) { rep, err in
    if let rep { print("thumbnail", rep.type.rawValue, rep.cgImage.width, "x", rep.cgImage.height) } else { print("error", err?.localizedDescription ?? "nil") }
    sem.signal()
}
_ = sem.wait(timeout: .now() + 40)
