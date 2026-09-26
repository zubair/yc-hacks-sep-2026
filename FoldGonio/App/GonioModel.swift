import AVFoundation
import Observation
import SwiftUI

/// App-wide state: the live hinge, the hold gate, and the saved patients.
/// The hinge belongs to the device, not a window, so every window shares one model.
@Observable @MainActor
final class GonioModel {
    static let patientID = DemoData.alexID

    private(set) var state: AppState
    /// The latest hinge from `onHingeChange`. It stays nil on devices without a hinge.
    private(set) var deviceHinge: HingeSample?
    /// Stands in for the hinge on devices without one, so the whole flow still demos on any simulator.
    private(set) var simulatedHinge = HingeSample(posture: .partiallyOpen, rawDegrees: 90)
    private(set) var gate = StabilityGate()
    /// Bumps on every capture, which drives the success haptic.
    private(set) var captureCount = 0
    /// Recording is on only while the Measure tab is on screen with no sheet over it.
    /// Otherwise a phone left in tabletop pose on a desk would log readings.
    private(set) var isArmed = false
    var speaksReadings = true

    private let store: StateStore
    private let speech = AVSpeechSynthesizer()

    init(store: StateStore = .standard()) {
        self.store = store
        if let saved = store.load() {
            state = saved
        } else {
            state = DemoData.state(now: .now)
            persist()
        }
        // During a real measurement the inner display faces the back of the knee, so the reading is also spoken.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    // MARK: Hinge

    var hasDeviceHinge: Bool { deviceHinge != nil }
    var hinge: HingeSample { deviceHinge ?? simulatedHinge }
    var posture: HingeSample.Posture { hinge.posture }
    var calibration: Calibration { state.calibration }
    var flexion: Double { calibration.flexion(raw: hinge.rawDegrees) }

    func ingest(_ sample: HingeSample?) {
        guard let sample else { return }
        deviceHinge = sample
        stepGate()
    }

    func setArmed(_ armed: Bool) {
        isArmed = armed
        stepGate()
    }

    func setSimulatedHinge(rawDegrees: Double) {
        let posture: HingeSample.Posture = switch rawDegrees {
        case ..<2: .closed
        case 178...: .fullyOpen
        default: .partiallyOpen
        }
        simulatedHinge = HingeSample(posture: posture, rawDegrees: rawDegrees)
        stepGate()
    }

    /// Hinge updates stop while the phone is still, so a clock also drives the hold timer.
    func runGateClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            stepGate()
        }
    }

    private func stepGate(now: Date = .now) {
        let angle: Double? = isArmed && hinge.isMeasurable ? flexion : nil
        var next = gate
        let captured = next.step(angle, at: now)
        // Assign only on change, so the 10 Hz clock doesn't redraw every observer.
        if next != gate { gate = next }
        if let captured { record(captured, at: now) }
    }

    private func record(_ flexion: Double, at date: Date) {
        let previousBest = summary(for: patient, now: date).today
        updatePatient { $0.readings.append(Reading(date: date, flexion: flexion)) }
        captureCount += 1
        let isNewBest = previousBest.map { flexion.rounded() > $0.rounded() } ?? true
        announce(flexion, isNewBest: isNewBest)
    }

    private func announce(_ flexion: Double, isNewBest: Bool) {
        guard speaksReadings else { return }
        let text = "\(Int(flexion.rounded())) degrees" + (isNewBest ? ". Best today." : ".")
        speech.stopSpeaking(at: .immediate)
        speech.speak(AVSpeechUtterance(string: text))
    }

    // MARK: Patients

    var patient: Patient {
        self.patient(withID: Self.patientID) ?? state.patients.first ?? DemoData.alex(now: .now)
    }

    func patient(withID id: Patient.ID?) -> Patient? {
        state.patients.first { $0.id == id }
    }

    func summary(for patient: Patient, now: Date = .now) -> RecoverySummary {
        Recovery.summary(for: patient, now: now, calendar: .current)
    }

    var report: String {
        PTReport.text(for: patient, calibration: calibration, now: .now, calendar: .current)
    }

    func deleteReadings(_ ids: Set<Reading.ID>) {
        updatePatient { $0.readings.removeAll { ids.contains($0.id) } }
    }

    /// Re-seeds both patients relative to today and keeps the calibration, which belongs to this phone.
    func resetDemoData() {
        let calibration = state.calibration
        state = DemoData.state(now: .now)
        state.calibration = calibration
        gate.reset()
        persist()
    }

    private func updatePatient(_ change: (inout Patient) -> Void) {
        guard let index = state.patients.firstIndex(where: { $0.id == Self.patientID }) else { return }
        change(&state.patients[index])
        persist()
    }

    // MARK: Calibration

    enum CalibrationError: LocalizedError {
        case notPartlyOpen
        case notASquare(Double)

        var errorDescription: String? {
            switch self {
            case .notPartlyOpen:
                "Open the phone partway so it can sit in the corner."
            case .notASquare(let raw):
                "The hinge reads \(Format.degrees1(raw)), too far from 90° to be a square. Seat both halves flat against the sides and try again."
            }
        }
    }

    func calibrateAgainstSquare() throws {
        guard hinge.isMeasurable else { throw CalibrationError.notPartlyOpen }
        guard let calibration = Calibration.square(rawDegrees: hinge.rawDegrees, at: .now) else {
            throw CalibrationError.notASquare(hinge.rawDegrees)
        }
        state.calibration = calibration
        persist()
    }

    func clearCalibration() {
        state.calibration = .uncalibrated
        persist()
    }

    private func persist() {
        do {
            try store.save(state)
        } catch {
            print("FoldGonio: couldn't save state: \(error)")
        }
    }
}

extension HingeSample {
    init(_ hinge: DeviceHinge) {
        // `DeviceHinge.Status` is a struct with static members, not an enum.
        let posture: Posture = switch hinge.status {
        case .closed: .closed
        case .partiallyOpen: .partiallyOpen
        case .fullyOpen: .fullyOpen
        default: .unknown
        }
        self.init(posture: posture, rawDegrees: hinge.angle.degrees)
    }
}
