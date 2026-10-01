import XCTest

/// Real-window flows, each run on both renderers (`-GLTFRenderer` launch override). Screenshots
/// are kept in the xcresult as evidence.
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

    func testOpenRealityKit() { openGLB(.realityKit) }
    func testOpenWebKit() { openGLB(.webKit) }

    private func openGLB(_ renderer: UIRenderer) {
        let app = launch(renderer)
        let marker = waitForCanvas(in: app)
        XCTAssertEqual(marker.label, renderer.rawValue)
        attachScreenshot(app, named: "open-\(renderer.rawValue)")
    }

    // MARK: 2. View menu: wireframe, Fit, Reset View

    func testViewModesRealityKit() { viewModes(.realityKit) }
    func testViewModesWebKit() { viewModes(.webKit) }

    private func viewModes(_ renderer: UIRenderer) {
        let app = launch(renderer)
        waitForCanvas(in: app)

        clickMenu(app, "View", "View Mode", "Wireframe")
        attachScreenshot(app, named: "wireframe-\(renderer.rawValue)")

        clickMenu(app, "View", "Fit")
        XCTAssertTrue(canvasReady(in: app).exists)
        clickMenu(app, "View", "Reset View")
        XCTAssertTrue(canvasReady(in: app).exists)

        clickMenu(app, "View", "View Mode", "Shaded")
        XCTAssertTrue(canvasReady(in: app).exists)
        attachScreenshot(app, named: "shaded-after-reset-\(renderer.rawValue)")
    }

    // MARK: 3. Outliner selection → inspector

    func testOutlinerSelectionRealityKit() { outlinerSelection(.realityKit) }
    func testOutlinerSelectionWebKit() { outlinerSelection(.webKit) }

    private func outlinerSelection(_ renderer: UIRenderer) {
        let app = launch(renderer)
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
        attachScreenshot(app, named: "selection-\(renderer.rawValue)")
    }

    private func launch(_ renderer: UIRenderer) -> XCUIApplication {
        let app = makeApp(renderer: renderer, file: UIFixture.boxAnimated)
        app.launch()
        self.app = app
        return app
    }
}
