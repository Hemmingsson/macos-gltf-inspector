import XCTest

/// Shared launch / query helpers. Accessibility only: no app module is imported.
enum UIFixture {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Animated box GLB with unnamed nodes (`Node 0` … in the outliner).
    static let boxAnimated = repoRoot.appendingPathComponent("TestModels/Fixture Models/BoxAnimated/BoxAnimated.glb")
    /// Single named mesh node (`Cube`) centred in the default view.
    static let cube = repoRoot.appendingPathComponent("TestModels/Fixture Models/cube/cube.gltf")
}

enum UIWait {
    static let timeout: TimeInterval = 30
}

extension XCTestCase {
    /// A fresh app process; `file` is opened from argv like `open -a`.
    func makeApp(file: URL?) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ApplePersistenceIgnoreState", "YES"]
        if let file {
            arguments.append(file.path)
        }
        app.launchArguments = arguments
        return app
    }

    /// `canvasReadyMarker`: exists only while the canvas shows the model.
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

    func documentReady(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "document-ready").firstMatch
    }

    @discardableResult
    func waitForDocument(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let marker = documentReady(in: app)
        XCTAssertTrue(
            marker.waitForExistence(timeout: UIWait.timeout),
            "document panels never became ready",
            file: file,
            line: line
        )
        return marker
    }

    func inspectorSelection(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "inspector-selection").firstMatch
    }

    /// Clicks the sidebar outliner when rows are not exposed in the accessibility tree.
    func clickSidebarOutliner(in app: XCUIApplication, normalizedY: CGFloat = 0.42) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: UIWait.timeout), "window missing")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: normalizedY)).click()
    }

    /// Clicks the canvas detail area (between sidebar and inspector), near the visual centre.
    func clickCanvasCentre(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: UIWait.timeout), "window missing")
        // Below the title-bar band; past the ~248 pt sidebar on the default 1280 pt window.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.55)).click()
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
