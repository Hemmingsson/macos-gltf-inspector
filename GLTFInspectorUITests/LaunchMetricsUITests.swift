import XCTest

/// Launch and open-to-first-content timings (3 iterations each). Open-to-content = launch with a
/// file until the host's `canvas-ready` marker appears (RealityKit: convert landed and the canvas
/// mounted; WebKit: the page reports the model on screen).
final class LaunchMetricsUITests: XCTestCase {
    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    func testLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            makeApp(renderer: nil, file: nil).launch()
        }
        XCUIApplication().terminate()
    }

    func testOpenToContentRealityKit() { openToContent(.realityKit) }
    func testOpenToContentWebKit() { openToContent(.webKit) }

    private func openToContent(_ renderer: UIRenderer) {
        let options = options
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            let app = makeApp(renderer: renderer, file: UIFixture.boxAnimated)
            app.launch()
            // Polls `exists` directly: `waitForExistence` re-checks only about once a second,
            // which would round the measurement up to whole seconds.
            let marker = canvasReady(in: app)
            let deadline = Date().addingTimeInterval(UIWait.timeout)
            while !marker.exists, Date() < deadline {}
            XCTAssertTrue(marker.exists, "canvas never became ready")
            stopMeasuring()
            app.terminate()
        }
    }
}
