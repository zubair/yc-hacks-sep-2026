import Foundation
import Testing
@testable import GonioCore

@Suite("Hinge to flexion")
struct CalibrationTests {
    @Test func flatPhoneIsAStraightKnee() {
        #expect(Calibration.uncalibrated.flexion(raw: 180) == 0)
    }

    @Test func hingeAngleIsTheAngleBehindTheKnee() {
        // 104° of flexion leaves 76° between the thigh and shin halves.
        #expect(Calibration.uncalibrated.flexion(raw: 76) == 104)
    }

    @Test func squareCalibrationRemovesAConstantOffset() throws {
        // This hinge reads 2° high.
        let calibration = try #require(Calibration.square(rawDegrees: 92, at: .now))
        #expect(calibration.offset == -2)
        #expect(calibration.isCalibrated)
        #expect(calibration.flexion(raw: 78) == 104)
    }

    @Test func refusesAReadingThatIsNotASquare() {
        #expect(Calibration.square(rawDegrees: 60, at: .now) == nil)
        #expect(Calibration.square(rawDegrees: 120, at: .now) == nil)
    }

    @Test func clampsToThePhysicalRange() {
        let calibration = Calibration(offset: 5, calibratedAt: .now)
        #expect(calibration.hingeDegrees(raw: 179) == 180)
        #expect(calibration.flexion(raw: 179) == 0)
        #expect(Calibration(offset: -5, calibratedAt: .now).hingeDegrees(raw: 2) == 0)
    }

    @Test func onlyPartlyOpenIsMeasurable() {
        #expect(HingeSample(posture: .partiallyOpen, rawDegrees: 90).isMeasurable)
        #expect(!HingeSample(posture: .fullyOpen, rawDegrees: 180).isMeasurable)
        #expect(!HingeSample(posture: .closed, rawDegrees: 0).isMeasurable)
        #expect(!HingeSample(posture: .unknown, rawDegrees: 90).isMeasurable)
    }
}

@Suite("One-second hold")
struct StabilityGateTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func waitsForAFullSecond() {
        var gate = StabilityGate()
        #expect(gate.step(104, at: t0) == nil)
        #expect(gate.step(104, at: t0 + 0.99) == nil)
        #expect(gate.step(104, at: t0 + 1.0) == 104)
    }

    @Test func firesOncePerHold() {
        var gate = StabilityGate()
        _ = gate.step(104, at: t0)
        #expect(gate.step(104, at: t0 + 1) == 104)
        #expect(gate.step(104, at: t0 + 2) == nil)
        #expect(gate.step(104.5, at: t0 + 3) == nil)
        #expect(gate.phase(at: t0 + 3) == .captured(104))
    }

    @Test func smallWobbleStillCountsAsHolding() {
        var gate = StabilityGate()
        _ = gate.step(100, at: t0)
        _ = gate.step(101.2, at: t0 + 0.4)
        _ = gate.step(99.1, at: t0 + 0.8)
        #expect(gate.step(100.4, at: t0 + 1.1) == 100.4)
    }

    @Test func movingRestartsTheHold() {
        var gate = StabilityGate()
        _ = gate.step(90, at: t0)
        _ = gate.step(95, at: t0 + 0.9)
        #expect(gate.step(95, at: t0 + 1.2) == nil)
        #expect(gate.step(95, at: t0 + 1.9) == 95)
    }

    @Test func bendingFurtherAfterACaptureRecordsAgain() {
        var gate = StabilityGate()
        _ = gate.step(100, at: t0)
        #expect(gate.step(100, at: t0 + 1) == 100)
        _ = gate.step(104, at: t0 + 2)
        #expect(gate.step(104, at: t0 + 3) == 104)
    }

    @Test func clockTicksCaptureWithoutNewHingeUpdates() {
        // A still phone sends no hinge updates. The clock re-sends the last angle.
        var gate = StabilityGate()
        let last = 104.0
        _ = gate.step(last, at: t0)
        var captured: Double?
        for tick in 1...12 {
            if let value = gate.step(last, at: t0 + Double(tick) * 0.1) {
                captured = value
            }
        }
        #expect(captured == 104)
    }

    @Test func leavingPartlyOpenResets() {
        var gate = StabilityGate()
        _ = gate.step(104, at: t0)
        _ = gate.step(nil, at: t0 + 0.5)
        #expect(gate.phase(at: t0 + 0.5) == .idle)
        #expect(gate.step(104, at: t0 + 1.0) == nil)
        #expect(gate.step(104, at: t0 + 2.0) == 104)
    }

    @Test func reportsProgress() {
        var gate = StabilityGate()
        _ = gate.step(104, at: t0)
        #expect(gate.phase(at: t0 + 0.5) == .holding(progress: 0.5))
        #expect(gate.isHolding)
    }
}

@Suite("Fold layout")
struct LegGeometryTests {
    @Test func horizontalFoldPutsTheKneeOnTheCrease() {
        // Portrait inner display, partly folded: a 40 pt division region across the middle.
        let fold = CGRect(x: 0, y: 455, width: 669, height: 40)
        let geometry = LegGeometry(fold: fold, size: CGSize(width: 669, height: 951))
        #expect(geometry.isHorizontalFold)
        #expect(geometry.knee == CGPoint(x: 334.5, y: 475))
        #expect(geometry.hip.y < geometry.knee.y)
        #expect(geometry.ankle.y > geometry.knee.y)
        #expect(geometry.firstHalf.maxY == fold.minY)
        #expect(geometry.secondHalf.minY == fold.maxY)
        #expect(geometry.secondHalf.maxY == 951)
    }

    @Test func verticalFoldPutsThighAndShinSideBySide() {
        let fold = CGRect(x: 455, y: 0, width: 40, height: 669)
        let geometry = LegGeometry(fold: fold, size: CGSize(width: 951, height: 669))
        #expect(!geometry.isHorizontalFold)
        #expect(geometry.knee == CGPoint(x: 475, y: 334.5))
        #expect(geometry.hip.x < geometry.knee.x)
        #expect(geometry.ankle.x > geometry.knee.x)
        #expect(geometry.firstHalf.maxX == fold.minX)
        #expect(geometry.secondHalf.minX == fold.maxX)
    }
}
