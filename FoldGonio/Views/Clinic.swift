import SwiftUI

/// The clinician's patient list. Each patient opens in its own window, so two can sit side by
/// side on the inner display.
struct ClinicSheet: View {
    @Environment(GonioModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.state.patients) { patient in
                        Button {
                            openWindow(id: "patient", value: patient.id)
                        } label: {
                            PatientRow(patient: patient, summary: model.summary(for: patient))
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Each patient opens in a new window. Open two, then drag one to the side of the inner display to compare them.")
                }
            }
            .navigationTitle("Clinic")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PatientRow: View {
    let patient: Patient
    let summary: RecoverySummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(patient.name)
                    .font(.headline)
                Text("\(patient.joint) · day \(summary.postOpDay)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if summary.isPlateau {
                    Label("Plateau", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if let slope = summary.slope {
                    Text(Format.rate(slope))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
            Spacer()
            Text(summary.current.map(Format.degrees) ?? "—")
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Image(systemName: "macwindow.badge.plus")
                .foregroundStyle(.tint)
        }
        .contentShape(.rect)
    }
}

struct PatientWindow: View {
    let patientID: Patient.ID?
    @Environment(GonioModel.self) private var model

    var body: some View {
        if let patient = model.patient(withID: patientID) {
            let summary = model.summary(for: patient)
            NavigationStack {
                List {
                    Section {
                        TodayGlance(patient: patient)
                            .padding(.vertical, 4)
                        RecoveryChart(patient: patient, summary: summary)
                            .frame(height: 260)
                            .padding(.vertical, 8)
                    } header: {
                        Text("\(patient.joint) · day \(summary.postOpDay)")
                    }

                    Section("Daily best") {
                        ForEach(summary.bests.reversed()) { best in
                            LabeledContent("Day \(best.postOpDay)", value: Format.degrees(best.flexion))
                                .monospacedDigit()
                        }
                    }
                }
                .navigationTitle(patient.name)
            }
        } else {
            ContentUnavailableView("Patient not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}
