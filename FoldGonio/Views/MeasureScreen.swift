import SwiftUI

/// Picks the layout from the fold's reserved region, as Apple recommends, not from the hinge angle.
/// - Partly folded (active division region): the leg across the fold.
/// - Otherwise: a split with the live dial as the primary pane and the recovery curve as the
///   secondary pane. It's side by side when unfolded and stacked on the outer display.
struct MeasureScreen: View {
    var body: some View {
        GeometryReader { proxy in
            // Only active regions, and the fold is active only while the phone is partly folded.
            let fold = proxy.reservedRegions(kind: .division).first?.frame

            Group {
                if let fold {
                    FoldLegView(fold: fold, size: proxy.size)
                } else {
                    ReviewArrangement()
                }
            }
            .transition(.blurReplace)
            .animation(.smooth, value: fold)
        }
    }
}

private struct ReviewArrangement: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        ArrangementView {
            DialPane()
                .splitArrangementLayoutRatio(0.45)
        } secondary: {
            RecoveryPane(patient: model.patient)
        }
        .arrangementViewStyle(.split.axes([.horizontal, .vertical]))
    }
}

/// With the phone closed, the dial can't measure, so it becomes today's summary on the outer display.
private struct DialPane: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        if model.posture == .closed {
            VStack(alignment: .leading, spacing: 16) {
                TodayGlance(patient: model.patient)
                Label("Open halfway to measure", systemImage: "book.pages")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.teal)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            LiveDial()
        }
    }
}

private struct LiveDial: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PostureChip()
                LegSideView(flexion: model.flexion)
                    .frame(maxWidth: 360)
                    .frame(height: 180)
                AngleReadout(flexion: model.flexion, isLive: model.hinge.isMeasurable)
                HoldStatus()
                if !model.hasDeviceHinge {
                    SimulatedHingeControls()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct RecoveryPane: View {
    let patient: Patient
    @Environment(GonioModel.self) private var model

    var body: some View {
        let summary = model.summary(for: patient)
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery")
                .font(.title3.bold())
            TrendLine(summary: summary)
            RecoveryChart(patient: patient, summary: summary)
                .frame(minHeight: 180)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
