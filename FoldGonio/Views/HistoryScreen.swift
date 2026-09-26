import SwiftUI

struct HistoryScreen: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let patient = model.patient
        let summary = model.summary(for: patient)
        let readings = patient.readings.sorted { $0.date > $1.date }

        List {
            Section {
                TodayGlance(patient: patient)
                    .padding(.vertical, 4)
                RecoveryChart(patient: patient, summary: summary)
                    .frame(height: 240)
                    .padding(.vertical, 8)
            } header: {
                Text("\(patient.name) · \(patient.joint) · day \(summary.postOpDay)")
            }

            Section("Readings") {
                ForEach(readings) { reading in
                    HStack {
                        Text(Format.degrees(reading.flexion))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text(reading.date, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    model.deleteReadings(Set(offsets.map { readings[$0].id }))
                }
            }

            Section {
                Toggle("Speak each reading", systemImage: "speaker.wave.2", isOn: $model.speaksReadings)
                Button("Reset Demo Data", systemImage: "arrow.counterclockwise", role: .destructive) {
                    model.resetDemoData()
                }
            } footer: {
                Text("The inner display faces the back of the knee while you measure, so each reading is also spoken. Resetting re-seeds the demo patients and keeps the calibration.")
            }
        }
    }
}
