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

    // MARK: 3. Outliner selection → inspector

    func testOutlinerSelection() {
        let app = launch()
        waitForCanvas(in: app)

        // `NodeRow` label: "<name>, <kind>". BoxAnimated's nodes are unnamed → "Node <index>".
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Node 1, "))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: UIWait.timeout), "outliner row Node 1 missing")
        row.click()

        let inspector = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Inspector"))
            .firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: UIWait.timeout), "inspector missing")
        // `NodeHeader` combines name and kind into one text: "Node 1, Group".
        let header = inspector.staticTexts
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Node 1,"))
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: UIWait.timeout), "inspector does not show Node 1")
        attachScreenshot(app, named: "selection")
    }

    private func launch() -> XCUIApplication {
        let app = makeApp(file: UIFixture.boxAnimated)
        app.launch()
        self.app = app
        return app
    }
}
