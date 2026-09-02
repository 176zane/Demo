import SwiftUI

/// 根路由：权限页 ↔ 三 Tab 主流程
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.rootScreen {
            case .permission:
                PermissionView()
            case .review:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.rootScreen)
        .onAppear {
            // 首帧再读一次：init 时 PhotoKit 偶发仍报 notDetermined
            appState.refreshAuth()
        }
    }
}
