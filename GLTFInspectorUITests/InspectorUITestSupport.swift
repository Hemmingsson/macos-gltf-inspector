import XCTest

/// Shared launch / query helpers. Accessibility only: no app or renderer module is imported, so
/// removing a renderer needs no edit here.
enum UIRenderer: String, CaseIterable {
    case realityKit = "realitykit"
    case webKit = "webkit"

    /// Settings ▸ Preview ▸ Renderer menu title (`RendererRouter.settingsOptions`).
    var settingsTitle: String {
        switch self {
        case .realityKit: "RealityKit"
        case .webKit: "WebKit (Khronos)"
        }
    }

    init?(settingsTitle: String) {
        guard let kind = Self.allCases.first(where: { $0.settingsTitle == settingsTitle }) else { return nil }
        self = kind
    }
}

enum UIFixture {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Animated box GLB with unnamed nodes (`Node 0` … in the outliner).
    static let boxAnimated = repoRoot.appendingPathComponent("TestModels/Fixture Models/BoxAnimated/BoxAnimated.glb")
}

enum UIWait {
    static let timeout: TimeInterval = 30
}

extension XCTestCase {
    /// A fresh app process. `renderer` is the Debug-only `-GLTFRenderer` override (nil = the stored
    /// Settings switch); `file` is opened from argv like `open -a`.
    func makeApp(renderer: UIRenderer?, file: URL?) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ApplePersistenceIgnoreState", "YES"]
        if let renderer {
            arguments += ["-GLTFRenderer", renderer.rawValue]
        }
        if let file {
            arguments.append(file.path)
        }
        app.launchArguments = arguments
        return app
    }

    /// Host `CanvasReadyMarker`: exists only while the canvas shows the model; label = renderer.
    func canvasReady(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "canvas-ready").firstMatch
    }

    @discardableResult
    func waitForCanvas(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let marker = canvasReady(in: app)
        XCTAssertTrue(
            marker.waitForExistence(timeout: UIWait.timeout),
            "canvas never became ready",
            file: file,
            line: line
        )
        return marker
    }

    func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let window = app.windows.firstMatch
        let screenshot = window.exists ? window.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Clicks a top-level menu bar item, then a path of (sub)menu items.
    func clickMenu(_ app: XCUIApplication, _ top: String, _ path: String...) {
        app.menuBars.menuBarItems[top].click()
        var menu = app.menuBars.menuBarItems[top]
        for title in path {
            let item = menu.menuItems[title]
            XCTAssertTrue(item.waitForExistence(timeout: UIWait.timeout), "menu item \(title) missing")
            item.click()
            menu = item
        }
    }
}
