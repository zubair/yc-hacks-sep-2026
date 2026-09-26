import SwiftUI

/// Measure and History are tabs, and Send to PT is a pinned action. Each has a title and an SF Symbol,
/// so the system can move them into the vertical bar along the side of the outer display, and of the
/// inner display in landscape.
struct RootView: View {
    @Environment(GonioModel.self) private var model
    @State private var tab = AppTab.measure
    @State private var sheet: SheetKind?

    var body: some View {
        TabView(selection: $tab) {
            Tab("Measure", systemImage: "angle", value: AppTab.measure) {
                NavigationStack {
                    MeasureScreen()
                        .navigationTitle("Measure")
                        .toolbarTitleDisplayMode(.inline)
                        .toolbar { toolbarContent }
                }
            }
            Tab("History", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.history) {
                NavigationStack {
                    HistoryScreen()
                        .navigationTitle("History")
                        .toolbar { toolbarContent }
                }
            }
        }
        .onHingeChange { _, context in
            model.ingest(context.hinge.map { HingeSample($0) })
        }
        .task { await model.runGateClock() }
        .onChange(of: tab == .measure && sheet == nil, initial: true) { _, armed in
            model.setArmed(armed)
        }
        .sensoryFeedback(.success, trigger: model.captureCount)
        .sheet(item: $sheet) { kind in
            switch kind {
            case .calibration: CalibrationSheet()
            case .clinic: ClinicSheet()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The one action a patient comes back for, pinned so it never overflows.
        ToolbarItem(placement: .topBarPinnedTrailing) {
            ShareLink(item: model.report, subject: Text("Knee range of motion")) {
                Label("Send to PT", systemImage: "paperplane")
            }
        }
        ToolbarOverflowMenu {
            Button("Calibrate", systemImage: "ruler") { sheet = .calibration }
            Button("Clinician View", systemImage: "stethoscope") { sheet = .clinic }
        }
    }
}

private enum AppTab: Hashable {
    case measure, history
}

private enum SheetKind: String, Identifiable {
    case calibration, clinic
    var id: Self { self }
}
