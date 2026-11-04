import XCTest

/// Real-window flows. Screenshots are kept in the xcresult as evidence.
final class DocumentWindowUITests: XCTestCase {
    private var app: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
    }

    // MARK: 1. Open a GLB from argv

    func testOpen() {
        let app = launch()
        waitForCanvas(in: app)
        attachScreenshot(app, named: "open")
    }

    // MARK: 2. View menu: wireframe, Fit, Reset View

    func testViewModes() {
        let app = launch()
        waitForCanvas(in: app)

        clickMenu(app, "View", "View Mode", "Wireframe")
        attachScreenshot(app, named: "wireframe")

        clickMenu(app, "View", "Fit")
        XCTAssertTrue(canvasReady(in: app).exists)
        clickMenu(app, "View", "Reset View")
        XCTAssertTrue(canvasReady(in: app).exists)

        clickMenu(app, "View", "View Mode", "Shaded")
        XCTAssertTrue(canvasReady(in: app).exists)
        attachScreenshot(app, named: "shaded-after-reset")
    }

    // MARK: 3. Canvas click → selection

    func testCanvasPickSelectsMesh() {
        let app = makeApp(file: UIFixture.cube)
        app.launch()
        self.app = app
        waitForCanvas(in: app)
        waitForDocument(in: app)

        clickCanvasCentre(in: app)

        let header = inspectorSelection(in: app)
        XCTAssertTrue(header.waitForExistence(timeout: UIWait.timeout), "inspector does not show Cube")
        XCTAssertTrue(header.label.contains("Cube"), "expected Cube selection, got \(header.label)")
        attachScreenshot(app, named: "canvas-pick")
    }

    // MARK: 4. Outliner selection → inspector

    func testOutlinerSelection() {
        let app = launch()
        waitForCanvas(in: app)
        waitForDocument(in: app)

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Node 1, "))
            .firstMatch
        if row.waitForExistence(timeout: 2) {
            row.click()
        } else {
            clickSidebarOutliner(in: app)
        }

        let header = inspectorSelection(in: app)
        XCTAssertTrue(header.waitForExistence(timeout: UIWait.timeout), "inspector does not show Node 1")
        XCTAssertTrue(header.label.contains("Node 1"), "expected Node 1 selection, got \(header.label)")
        attachScreenshot(app, named: "selection")
    }

    private func launch() -> XCUIApplication {
        let app = makeApp(file: UIFixture.boxAnimated)
        app.launch()
        self.app = app
        return app
    }
}
