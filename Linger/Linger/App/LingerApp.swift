import SwiftUI

@main
struct LingerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.statsStore)
                .environmentObject(appState.preferencesStore)
        }
    }
}
