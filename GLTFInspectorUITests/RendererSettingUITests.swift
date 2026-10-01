import XCTest

/// Settings ▸ Preview ▸ Renderer: switching applies to the next window. Runs without the
/// `-GLTFRenderer` override and always puts the stored switch back to what it was.
final class RendererSettingUITests: XCTestCase {
    /// The stored renderer to put back if the test stops before restoring it.
    private var pendingRestore: UIRenderer?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        guard let original = pendingRestore else { return }
        let app = makeApp(renderer: nil, file: nil)
        app.launch()
        chooseRenderer(original, in: app)
        app.terminate()
        pendingRestore = nil
    }

    func testRendererSwitchAppliesToNextWindow() throws {
        let app = makeApp(renderer: nil, file: nil)
        app.launch()
        let original = try XCTUnwrap(selectedRenderer(app), "Renderer picker has no known value")
        let other: UIRenderer = original == .webKit ? .realityKit : .webKit
        pendingRestore = original

        chooseRenderer(other, in: app)
        attachScreenshot(app, named: "settings-\(other.rawValue)")
        app.terminate()
        XCTAssertEqual(openFileRenderer(), other.rawValue, "new window did not use the switched renderer")

        let again = makeApp(renderer: nil, file: nil)
        again.launch()
        chooseRenderer(original, in: again)
        again.terminate()
        pendingRestore = nil
        XCTAssertEqual(openFileRenderer(), original.rawValue, "stored renderer not restored")
    }

    /// Launches with the fixture and returns the canvas's renderer label.
    private func openFileRenderer() -> String? {
        let app = makeApp(renderer: nil, file: UIFixture.boxAnimated)
        app.launch()
        defer { app.terminate() }
        let marker = waitForCanvas(in: app)
        attachScreenshot(app, named: "reopen-\(marker.label)")
        return marker.label
    }

    private func openPreviewSettings(_ app: XCUIApplication) -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let tab = app.toolbars.buttons["Preview"]
        XCTAssertTrue(tab.waitForExistence(timeout: UIWait.timeout), "Settings Preview tab missing")
        tab.click()
        let picker = app.popUpButtons["Renderer"]
        XCTAssertTrue(picker.waitForExistence(timeout: UIWait.timeout), "Renderer picker missing")
        return picker
    }

    private func selectedRenderer(_ app: XCUIApplication) -> UIRenderer? {
        let picker = openPreviewSettings(app)
        return (picker.value as? String).flatMap(UIRenderer.init(settingsTitle:))
    }

    private func chooseRenderer(_ renderer: UIRenderer, in app: XCUIApplication) {
        let picker = app.popUpButtons["Renderer"].exists ? app.popUpButtons["Renderer"] : openPreviewSettings(app)
        picker.click()
        let item = picker.menuItems[renderer.settingsTitle]
        XCTAssertTrue(item.waitForExistence(timeout: UIWait.timeout), "menu item \(renderer.settingsTitle) missing")
        item.click()
        let selected = NSPredicate(format: "value == %@", renderer.settingsTitle)
        expectation(for: selected, evaluatedWith: picker)
        waitForExpectations(timeout: UIWait.timeout)
    }
}
