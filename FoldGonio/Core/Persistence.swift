import Foundation

struct AppState: Codable, Equatable, Sendable {
    var patients: [Patient]
    var calibration: Calibration
}

/// Saves the whole app state as one small JSON file.
struct StateStore: Sendable {
    let url: URL

    static func standard() -> StateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StateStore(url: base.appendingPathComponent("FoldGonio/state.json"))
    }

    func load() -> AppState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

/// Seeded patients so the curve, the outer-screen summary, and the clinician view have something
/// to show on stage. Dates are relative to "now", so the seed stays current.
enum DemoData {
    static let alexID = "alex"
    static let samID = "sam"

    /// Post-op day → best flexion. Missing days are skipped sessions. It stops at yesterday,
    /// so the live measurement on stage becomes today's point.
    static let alexCurve: [(day: Int, flexion: Double)] = [
        (3, 62), (4, 65), (5, 67), (6, 70), (8, 74), (9, 77), (10, 79), (11, 82), (12, 84),
        (14, 88), (15, 90), (16, 91), (17, 93), (18, 95), (20, 97), (21, 98), (22, 100), (23, 101),
    ]

    /// A second patient who has stalled short of the goal, so the side-by-side view has a contrast.
    static let samCurve: [(day: Int, flexion: Double)] = [
        (10, 90), (12, 96), (14, 101), (16, 106), (18, 110), (20, 113), (22, 116), (25, 118),
        (28, 119), (31, 120), (33, 120), (35, 121), (37, 120), (39, 121),
    ]

    static func state(now: Date, calendar: Calendar = .current) -> AppState {
        AppState(patients: [alex(now: now, calendar: calendar), sam(now: now, calendar: calendar)], calibration: .uncalibrated)
    }

    static func alex(now: Date, calendar: Calendar = .current) -> Patient {
        patient(id: alexID, name: "Alex", joint: "Right knee, total knee replacement", daysSinceSurgery: 24, goal: 110, curve: alexCurve, now: now, calendar: calendar)
    }

    static func sam(now: Date, calendar: Calendar = .current) -> Patient {
        patient(id: samID, name: "Sam", joint: "Left knee, ACL reconstruction", daysSinceSurgery: 40, goal: 135, curve: samCurve, now: now, calendar: calendar)
    }

    private static func patient(
        id: String, name: String, joint: String, daysSinceSurgery: Int, goal: Double,
        curve: [(day: Int, flexion: Double)], now: Date, calendar: Calendar
    ) -> Patient {
        let today = calendar.startOfDay(for: now)
        let surgery = calendar.date(byAdding: .day, value: -daysSinceSurgery, to: today) ?? today
        let readings = curve.map { point in
            let day = calendar.date(byAdding: .day, value: point.day, to: surgery) ?? surgery
            let morning = calendar.date(byAdding: .hour, value: 10, to: day) ?? day
            return Reading(date: morning, flexion: point.flexion)
        }
        return Patient(id: id, name: name, joint: joint, surgeryDate: surgery, goal: goal, readings: readings)
    }
}
