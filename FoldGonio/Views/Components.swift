import SwiftUI

struct AngleReadout: View {
    let flexion: Double
    /// False when the hinge isn't partly open. The number is shown dimmed and nothing records.
    let isLive: Bool
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(Format.degrees(flexion))
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: flexion))
                .animation(.snappy, value: Int(flexion.rounded()))
                .opacity(isLive ? 1 : 0.35)
            if alignment == .center {
                Text("knee flexion")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Knee flexion")
        .accessibilityValue("\(Int(flexion.rounded())) degrees")
    }
}

/// Fills over the one-second hold, then turns green when the reading is kept.
struct HoldRing: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !model.gate.isHolding)) { context in
            let phase = model.gate.phase(at: context.date)
            let (progress, color): (Double, Color) = switch phase {
            case .idle: (0, .orange)
            case .holding(let progress): (progress, .orange)
            case .captured: (1, .green)
            }
            ZStack {
                Circle()
                    .stroke(.orange.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .accessibilityHidden(true)
    }
}

struct HoldStatus: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !model.gate.isHolding)) { context in
            let (text, symbol, tint) = describe(model.gate.phase(at: context.date))
            Label(text, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)
        }
    }

    private func describe(_ phase: StabilityGate.Phase) -> (String, String, Color) {
        switch model.posture {
        case .closed:
            return ("Open the phone halfway to measure", "iphone.gen3", .secondary)
        case .fullyOpen:
            return ("Flat means a straight knee. Fold partway to measure.", "book.pages", .secondary)
        case .unknown:
            return ("Waiting for the hinge", "questionmark.circle", .secondary)
        case .partiallyOpen:
            guard model.isArmed else { return ("Paused", "pause.circle", .secondary) }
            switch phase {
            case .captured(let flexion):
                return ("Recorded \(Format.degrees(flexion))", "checkmark.circle.fill", .green)
            case .holding(let progress) where progress > 0.15:
                return ("Hold still…", "timer", .orange)
            default:
                return ("Hold still for 1 second to record", "hand.raised", .primary)
            }
        }
    }
}

struct PostureChip: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.posture.symbol)
            Text(model.posture.title)
            if !model.hasDeviceHinge {
                Text("Simulated")
                    .foregroundStyle(.orange)
            }
            Text(model.calibration.isCalibrated ? "Calibrated" : "Not calibrated")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: .capsule)
    }
}

/// Stands in for the hinge on a device without one, so any simulator can run the flow.
struct SimulatedHingeControls: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        let angle = Binding(
            get: { model.simulatedHinge.rawDegrees },
            set: { model.setSimulatedHinge(rawDegrees: $0) }
        )
        VStack(alignment: .leading, spacing: 6) {
            Label("No hinge on this device. Drag to simulate one.", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Slider(value: angle, in: 0...180) {
                Text("Hinge angle")
            } minimumValueLabel: {
                Text("0°")
            } maximumValueLabel: {
                Text("180°")
            }
        }
        .padding(12)
        .frame(maxWidth: 420)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
    }
}

/// "Today: 104° → goal 110°". This is the outer-display summary, and it's reused in History and the clinician windows.
struct TodayGlance: View {
    let patient: Patient
    @Environment(GonioModel.self) private var model

    var body: some View {
        let summary = model.summary(for: patient)
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.today.map(Format.degrees) ?? "—")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Image(systemName: "arrow.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("goal \(Format.degrees(patient.goal))")
                    .font(.title2.weight(.semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            ProgressView(value: min((summary.current ?? 0) / patient.goal, 1))
                .tint(summary.isPlateau ? Color.orange : Color.teal)
            TrendLine(summary: summary)
        }
    }
}

struct TrendLine: View {
    let summary: RecoverySummary

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(summary.isPlateau ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
    }

    private var text: String {
        var parts: [String] = []
        if summary.today == nil, let latest = summary.latest {
            parts.append("Last: \(Format.degrees(latest.flexion)) on day \(latest.postOpDay)")
        }
        if let remaining = summary.remaining {
            parts.append(remaining == 0 ? "Goal reached" : "\(Format.degrees(remaining)) to go")
        }
        if summary.isPlateau, let slope = summary.slope {
            parts.append("plateau at \(Format.rate(slope))")
        } else if let days = summary.daysToGoal, days > 0 {
            parts.append("about \(days) days at this pace")
        }
        return parts.isEmpty ? "No readings yet" : parts.joined(separator: " · ")
    }
}

extension HingeSample.Posture {
    var title: String {
        switch self {
        case .closed: "Closed"
        case .partiallyOpen: "Partly open"
        case .fullyOpen: "Flat"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .closed: "iphone.gen3"
        case .partiallyOpen: "laptopcomputer"
        case .fullyOpen: "ipad.landscape"
        case .unknown: "questionmark.circle"
        }
    }
}
