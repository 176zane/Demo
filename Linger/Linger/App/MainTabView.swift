import SwiftUI

/// 权限通过后的主壳层，统一承载照片、视频和统计三个入口。
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @State private var selectedTab: MainTab = .photos
    /// 已访问过的 Tab 保活，避免每次点击都重建 ViewModel / PhotoKit / AVPlayer
    @State private var loadedTabs: Set<MainTab> = [.photos]

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if loadedTabs.contains(.photos) {
                    PhotoReviewContainerView()
                        .opacity(selectedTab == .photos ? 1 : 0)
                        .allowsHitTesting(selectedTab == .photos)
                }

                if loadedTabs.contains(.videos) {
                    VideoReviewView(
                        photoLibrary: appState.photoLibrary,
                        statsStore: statsStore,
                        preferencesStore: preferencesStore,
                        isActive: selectedTab == .videos
                    )
                    .opacity(selectedTab == .videos ? 1 : 0)
                    .allowsHitTesting(selectedTab == .videos)
                }

                if loadedTabs.contains(.stats) {
                    StatsView()
                        .opacity(selectedTab == .stats ? 1 : 0)
                        .allowsHitTesting(selectedTab == .stats)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 禁止选中态动画波及整页内容，消除 iOS 18 切换卡顿
            .transaction { $0.animation = nil }

            FloatingTabBar(selection: $selectedTab)
                .padding(.bottom, 18)
                .padding(.top, 4)
        }
        .background(canvas)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: selectedTab) { _, tab in
            loadedTabs.insert(tab)
        }
        .task {
            // 首屏稳定后预挂载视频/统计 Tab，并让视频先完成后台抽组
            try? await Task.sleep(nanoseconds: 350_000_000)
            loadedTabs.insert(.videos)
            loadedTabs.insert(.stats)
        }
    }

    private var canvas: some View {
        LinearGradient(
            colors: [LingerTheme.canvasTop, LingerTheme.canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
