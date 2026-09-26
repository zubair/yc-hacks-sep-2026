import SwiftUI

@main
struct PostcardApp: App {
    @State private var coordinator: PostcardCoordinator

    init() {
        let runtime = AppRuntime.make()
        _coordinator = State(
            initialValue: PostcardCoordinator(service: runtime.service, mode: runtime.mode)
        )
    }

    var body: some Scene {
        WindowGroup {
            PostcardRootView(coordinator: coordinator)
        }
    }
}
