import SwiftUI

/// One-time setup: seat the phone in a 90° square and store the offset.
struct CalibrationSheet: View {
    @Environment(GonioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Open the phone into the inside corner of a box, or against a carpenter's square, so each half lies flat on one side.", systemImage: "square.split.bottomrightquarter")
                    Label("Tap Set 90° while it sits there.", systemImage: "hand.tap")
                } header: {
                    Text("One-time setup")
                } footer: {
                    Text("This removes a constant offset from the hinge reading. It can't fix error that changes across the range.")
                }

                Section("Live hinge") {
                    LabeledContent("Raw angle", value: Format.degrees1(model.hinge.rawDegrees))
                    LabeledContent("Corrected", value: Format.degrees1(model.calibration.hingeDegrees(raw: model.hinge.rawDegrees)))
                    LabeledContent("Offset", value: model.calibration.isCalibrated ? Format.signedDegrees(model.calibration.offset) : "None")
                }

                if !model.hasDeviceHinge {
                    Section("Simulated hinge") {
                        SimulatedHingeControls()
                    }
                }

                Section {
                    Button("Set 90°", systemImage: "checkmark.circle") {
                        do {
                            try model.calibrateAgainstSquare()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(!model.hinge.isMeasurable)

                    if model.calibration.isCalibrated {
                        Button("Clear Calibration", systemImage: "xmark.circle", role: .destructive) {
                            model.clearCalibration()
                        }
                    }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Calibrate")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Keep the live reading current even if the presenting view stops receiving updates under the sheet.
        .onHingeChange { _, context in
            model.ingest(context.hinge.map { HingeSample($0) })
        }
    }
}
