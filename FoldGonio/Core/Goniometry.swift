import Foundation

/// One hinge reading, kept separate from SwiftUI's `DeviceHinge`. That lets the measuring
/// logic run and be tested anywhere, and lets a simulated hinge stand in on devices without one.
struct HingeSample: Equatable, Sendable {
    enum Posture: String, Equatable, Sendable {
        case closed, partiallyOpen, fullyOpen, unknown
    }

    var posture: Posture
    /// The angle between the two halves on the display side: 0° closed, 180° flat.
    var rawDegrees: Double

    /// Readings count only while the phone is partly folded. Flat and closed are postures, not measurements.
    var isMeasurable: Bool { posture == .partiallyOpen }
}

/// Converts the hinge angle to knee flexion, with a one-point offset correction.
///
/// The inner display faces into the fold. With one half along the thigh and the other along
/// the shin, the fold opens toward the back of the knee, so the hinge angle is the angle
/// behind the knee, which is 180° with the leg straight. A PT records flexion, which is 180° minus that.
struct Calibration: Codable, Equatable, Sendable {
    static let referenceDegrees = 90.0
    /// A bigger correction means the phone wasn't seated in the square, so it's refused.
    static let maxOffset = 15.0
    static let uncalibrated = Calibration(offset: 0, calibratedAt: nil)

    /// Degrees added to every raw hinge reading.
    var offset: Double
    var calibratedAt: Date?

    var isCalibrated: Bool { calibratedAt != nil }

    /// Builds a calibration from a raw reading taken with the phone seated in a 90° square.
    /// Returns nil when the reading is too far from 90° to trust.
    static func square(rawDegrees: Double, at date: Date) -> Calibration? {
        let offset = referenceDegrees - rawDegrees
        guard abs(offset) <= maxOffset else { return nil }
        return Calibration(offset: offset, calibratedAt: date)
    }

    func hingeDegrees(raw: Double) -> Double {
        min(max(raw + offset, 0), 180)
    }

    func flexion(raw: Double) -> Double {
        180 - hingeDegrees(raw: raw)
    }
}

/// Records a reading only after the angle has held steady for `holdDuration`.
///
/// Hinge updates arrive only when the angle changes, so a phone held still sends none.
/// Call `step` on every update and also on a clock tick. It fires once per hold, and it
/// re-arms when the angle moves past `tolerance` or measuring stops.
struct StabilityGate: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case holding(progress: Double)
        case captured(Double)
    }

    var holdDuration: TimeInterval = 1.0
    /// How much wobble still counts as holding still, in degrees.
    var tolerance: Double = 1.5

    private(set) var anchorAngle: Double?
    private(set) var anchorDate: Date?
    private(set) var captured: Double?

    var isHolding: Bool { anchorDate != nil && captured == nil }

    /// Takes the latest angle, or nil when not measuring. Returns the angle to record, at most once per hold.
    mutating func step(_ angle: Double?, at now: Date) -> Double? {
        guard let angle else {
            reset()
            return nil
        }
        guard let anchorAngle, let anchorDate, abs(angle - anchorAngle) <= tolerance else {
            self.anchorAngle = angle
            self.anchorDate = now
            captured = nil
            return nil
        }
        guard captured == nil, now.timeIntervalSince(anchorDate) >= holdDuration else { return nil }
        captured = angle
        return angle
    }

    func phase(at now: Date) -> Phase {
        if let captured { return .captured(captured) }
        guard let anchorDate else { return .idle }
        let progress = now.timeIntervalSince(anchorDate) / holdDuration
        return .holding(progress: min(max(progress, 0), 1))
    }

    mutating func reset() {
        anchorAngle = nil
        anchorDate = nil
        captured = nil
    }
}
