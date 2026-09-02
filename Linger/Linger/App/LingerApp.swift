import PortalTransitions
import SwiftUI

@main
struct LingerApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Portal 浮层窗口：首页卡和详情槽之间的 hero 飞行画在这里
            PortalContainer {
                RootView()
                    .environmentObject(appState)
                    .environmentObject(appState.statsStore)
                    .environmentObject(appState.preferencesStore)
            }
        }
        // 从设置授权返回时重新读权限，避免一直停在授权页
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.refreshAuth()
            }
        }
    }
}
