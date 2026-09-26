import SwiftUI

@main
struct FoldGonioApp: App {
    @State private var model = GonioModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
        }

        // Clinician view: one window per patient, so two can sit side by side on the inner display.
        // New windows open only on the inner display.
        WindowGroup("Patient", id: "patient", for: Patient.ID.self) { $patientID in
            PatientWindow(patientID: patientID)
                .environment(model)
        }
    }
}
