import Foundation
@testable import GLTFInspector
import Testing

/// The slider stays continuous so macOS draws no tick-mark ruler under the track; the step lives
/// in the binding instead. Snapping walks a grid from the lower bound, so a value lands on the
/// step within floating-point noise, not on the exact decimal.
struct DSSliderTests {
    private func snapped(_ value: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        DSSlider<Double>.snap(value, in: range, step: step)
    }

    @Test
    func snapsToTheNearestStep() {
        #expect(snapped(0.43, in: -3...3, step: 0.1).isNear(0.4))
        #expect(snapped(0.46, in: -3...3, step: 0.1).isNear(0.5))
        #expect(snapped(48.7, in: 10...120, step: 1).isNear(49))
    }

    /// The grid starts at the lower bound, so an off-grid range still lands on reachable values.
    @Test
    func snapsOnAGridFromTheLowerBound() {
        #expect(snapped(10.4, in: 10.25...12, step: 0.5).isNear(10.25))
        #expect(snapped(10.6, in: 10.25...12, step: 0.5).isNear(10.75))
    }

    @Test
    func clampsToTheRange() {
        #expect(snapped(99, in: -3...3, step: 0.1) == 3)
        #expect(snapped(-99, in: -3...3, step: 0.1) == -3)
    }

    /// The detents: both ends and the rest point. Everything between is silent, so a drag across
    /// a long range does not buzz the whole way.
    @Test
    func landmarksAreTheEndsAndTheRestPoint() {
        #expect(DSSlider<Double>.isLandmark(-3, in: -3...3, neutralValue: 0))
        #expect(DSSlider<Double>.isLandmark(3, in: -3...3, neutralValue: 0))
        #expect(DSSlider<Double>.isLandmark(0, in: -3...3, neutralValue: 0))
        #expect(!DSSlider<Double>.isLandmark(1.5, in: -3...3, neutralValue: 0))
        #expect(!DSSlider<Double>.isLandmark(-2.9, in: -3...3, neutralValue: 0))
    }

    /// Without a rest point only the ends tick.
    @Test
    func aSliderWithoutANeutralValueHasOnlyTwoLandmarks() {
        #expect(DSSlider<Double>.isLandmark(10, in: 10...120, neutralValue: nil))
        #expect(DSSlider<Double>.isLandmark(120, in: 10...120, neutralValue: nil))
        #expect(!DSSlider<Double>.isLandmark(11, in: 10...120, neutralValue: nil))
        #expect(!DSSlider<Double>.isLandmark(49, in: 10...120, neutralValue: nil))
    }

    /// About 40 notches across any track: the exposure slider's 60 steps and the environment
    /// slider's 360 land in the same ballpark, so neither crawls nor buzzes.
    @Test
    func aFullDragGivesAboutFortyDetents() {
        func detents(in range: ClosedRange<Double>, step: Double) -> Int {
            let low = DSSlider<Double>.detentIndex(range.lowerBound, in: range, step: step)
            let high = DSSlider<Double>.detentIndex(range.upperBound, in: range, step: step)
            return high - low
        }
        #expect((20...40).contains(detents(in: -3...3, step: 0.1)))      // exposure, 60 steps
        #expect((20...40).contains(detents(in: 0...360, step: 1)))       // environment, 360 steps
        #expect((20...40).contains(detents(in: 10...120, step: 1)))      // field of view, 110 steps
    }

    /// Detents sit on whole steps, so every notch is a value the slider can actually stop on.
    @Test
    func neighbouringStepsShareOrAdvanceOneDetent() {
        let indices = stride(from: 0.0, through: 360.0, by: 1).map {
            DSSlider<Double>.detentIndex($0, in: 0...360, step: 1)
        }
        #expect(indices.first == 0)
        #expect(zip(indices, indices.dropFirst()).allSatisfy { $1 - $0 == 0 || $1 - $0 == 1 })
    }

    @Test
    func aStepOfZeroLeavesTheValueAlone() {
        #expect(snapped(0.123_456, in: -3...3, step: 0) == 0.123_456)
    }
}

private extension Double {
    /// Within a step's worth of floating-point noise.
    func isNear(_ other: Double) -> Bool { abs(self - other) < 1e-9 }
}
