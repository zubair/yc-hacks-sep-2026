import Charts
import SwiftUI

/// Daily best flexion by post-op day, with the goal line and a dashed projection at the current pace.
struct RecoveryChart: View {
    let patient: Patient
    let summary: RecoverySummary

    var body: some View {
        Chart {
            ForEach(summary.bests) { best in
                LineMark(
                    x: .value("Post-op day", best.postOpDay),
                    y: .value("Flexion", best.flexion),
                    series: .value("Series", "Daily best")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.teal)

                PointMark(
                    x: .value("Post-op day", best.postOpDay),
                    y: .value("Flexion", best.flexion)
                )
                .foregroundStyle(best.postOpDay == summary.postOpDay ? Color.orange : Color.teal)
                .symbolSize(best.postOpDay == summary.postOpDay ? 120 : 28)
            }

            ForEach(projection) { point in
                LineMark(
                    x: .value("Post-op day", point.postOpDay),
                    y: .value("Flexion", point.flexion),
                    series: .value("Series", "Projection")
                )
                .foregroundStyle(.teal.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }

            RuleMark(y: .value("Goal", patient.goal))
                .foregroundStyle(.orange.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal \(Format.degrees(patient.goal))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
        }
        .chartYScale(domain: yDomain)
        .chartXAxisLabel("Days since surgery")
        .chartYAxis {
            AxisMarks(values: .stride(by: 20)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let degrees = value.as(Double.self) {
                        Text("\(Int(degrees))°")
                    }
                }
            }
        }
        .accessibilityLabel("Recovery curve")
        .accessibilityValue(accessibilitySummary)
    }

    /// From the latest daily best to the goal, at the recent pace.
    private var projection: [DailyBest] {
        guard let latest = summary.latest, let days = summary.daysToGoal, days > 0 else { return [] }
        return [latest, DailyBest(postOpDay: latest.postOpDay + days, flexion: patient.goal)]
    }

    private var yDomain: ClosedRange<Double> {
        let values = summary.bests.map(\.flexion) + [patient.goal]
        let low = max(0, ((values.min() ?? 0) - 10) / 10).rounded(.down) * 10
        let high = (((values.max() ?? 180) + 10) / 10).rounded(.up) * 10
        return low...min(high, 180)
    }

    private var accessibilitySummary: String {
        guard let latest = summary.latest else { return "No readings" }
        return "Latest \(Format.degrees(latest.flexion)) on day \(latest.postOpDay), goal \(Format.degrees(patient.goal))"
    }
}
