import Foundation

struct Reading: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    /// Knee flexion in degrees: 0° straight, larger is more bent.
    var flexion: Double
}

struct Patient: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var joint: String
    var surgeryDate: Date
    /// Target flexion in degrees.
    var goal: Double
    var readings: [Reading]
}

struct DailyBest: Identifiable, Equatable, Sendable {
    var postOpDay: Int
    var flexion: Double
    var id: Int { postOpDay }
}

struct RecoverySummary: Equatable, Sendable {
    var goal: Double
    var postOpDay: Int
    var bests: [DailyBest]
    /// Today's best reading, if there is one.
    var today: Double?
    /// Degrees per day over the recent window.
    var slope: Double?
    /// Days until the goal at the current pace. Nil while on a plateau.
    var daysToGoal: Int?

    var latest: DailyBest? { bests.last }
    var current: Double? { today ?? latest?.flexion }
    var remaining: Double? { current.map { max(goal - $0, 0) } }

    /// Short of the goal and barely moving. This is what a PT would want flagged.
    var isPlateau: Bool {
        guard let slope, let remaining else { return false }
        return slope < Recovery.plateauSlope && remaining > 0
    }
}

enum Recovery {
    /// How many recent daily bests the trend line looks at.
    static let window = 7
    /// Below this many degrees per day, progress counts as stalled.
    static let plateauSlope = 0.5

    static func postOpDay(_ date: Date, surgery: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: surgery)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func dailyBests(for patient: Patient, calendar: Calendar) -> [DailyBest] {
        Dictionary(grouping: patient.readings) {
            postOpDay($0.date, surgery: patient.surgeryDate, calendar: calendar)
        }
        .map { day, readings in
            DailyBest(postOpDay: day, flexion: readings.map(\.flexion).max() ?? 0)
        }
        .sorted { $0.postOpDay < $1.postOpDay }
    }

    /// Least-squares slope in degrees per day over the last `window` daily bests.
    static func slope(of bests: [DailyBest], window: Int = window) -> Double? {
        let recent = bests.suffix(window)
        guard recent.count >= 3 else { return nil }
        let n = Double(recent.count)
        let xs = recent.map { Double($0.postOpDay) }
        let ys = recent.map(\.flexion)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return sxy / sxx
    }

    static func summary(for patient: Patient, now: Date, calendar: Calendar) -> RecoverySummary {
        let bests = dailyBests(for: patient, calendar: calendar)
        let day = postOpDay(now, surgery: patient.surgeryDate, calendar: calendar)
        var summary = RecoverySummary(
            goal: patient.goal,
            postOpDay: day,
            bests: bests,
            today: bests.last(where: { $0.postOpDay == day })?.flexion,
            slope: slope(of: bests)
        )
        if let remaining = summary.remaining, let slope = summary.slope, slope >= plateauSlope {
            summary.daysToGoal = Int((remaining / slope).rounded(.up))
        }
        return summary
    }
}

enum Format {
    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func degrees1(_ value: Double) -> String {
        String(format: "%.1f°", value)
    }

    static func signedDegrees(_ value: Double) -> String {
        let sign = value < -0.05 ? "-" : "+"
        return sign + String(format: "%.1f°", abs(value))
    }

    static func rate(_ degreesPerDay: Double) -> String {
        signedDegrees(degreesPerDay) + "/day"
    }
}

/// The plain-text summary behind "Send to PT".
enum PTReport {
    static func text(for patient: Patient, calibration: Calibration, now: Date, calendar: Calendar) -> String {
        let summary = Recovery.summary(for: patient, now: now, calendar: calendar)
        var lines = [
            "FoldGonio range-of-motion report: \(patient.name), \(patient.joint)",
            "Post-op day \(summary.postOpDay), \(now.formatted(date: .abbreviated, time: .omitted))",
            "",
        ]

        if let today = summary.today {
            var line = "Today's best flexion: \(Format.degrees(today)) (goal \(Format.degrees(patient.goal))"
            if let remaining = summary.remaining, remaining > 0 {
                line += ", \(Format.degrees(remaining)) to go"
            }
            lines.append(line + ")")
        } else if let latest = summary.latest {
            lines.append("No reading yet today. Last: \(Format.degrees(latest.flexion)) on day \(latest.postOpDay) (goal \(Format.degrees(patient.goal))).")
        } else {
            lines.append("No readings yet.")
        }

        if let slope = summary.slope {
            var line = "Trend over the last \(Recovery.window) readings: \(Format.rate(slope))"
            if summary.isPlateau {
                line += ", which is a plateau"
            } else if let days = summary.daysToGoal, days > 0 {
                line += ", so the goal is about \(days) days away at this pace"
            }
            lines.append(line)
        }

        if !summary.bests.isEmpty {
            lines.append("")
            lines.append("Daily best flexion:")
            for best in summary.bests.suffix(14).reversed() {
                lines.append("  Day \(best.postOpDay): \(Format.degrees(best.flexion))")
            }
        }

        lines.append("")
        lines.append("Method: the phone's hinge is used as goniometer arms, and a reading counts after a 1-second steady hold.")
        if let date = calibration.calibratedAt {
            lines.append("Calibrated against a 90° square on \(date.formatted(date: .abbreviated, time: .omitted)), offset \(Format.signedDegrees(calibration.offset)).")
        } else {
            lines.append("Not calibrated.")
        }
        lines.append("This is a home measurement, not a clinical device reading.")
        return lines.joined(separator: "\n")
    }
}
