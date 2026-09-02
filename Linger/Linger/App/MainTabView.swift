import SwiftUI

/// 权限通过后的主壳层，统一承载照片、视频和统计三个入口。
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @State private var selectedTab: MainTab = .photos
    /// 已访问过的 Tab 保活，避免每次点击都重建 ViewModel / PhotoKit / AVPlayer
    @State private var loadedTabs: Set<MainTab> = [.photos]
    /// 照片详情 overlay 打开时隐藏底栏，避免挡住全屏浏览
    @State private var hideTabBarForBrowse = false

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
            // 仅在切 Tab 时关掉隐式动画，避免波及照片英雄转场
            .transaction(value: selectedTab) { $0.animation = nil }

            FloatingTabBar(selection: $selectedTab)
                .padding(.bottom, 18)
                .padding(.top, 4)
                .opacity(hideTabBarForBrowse ? 0 : 1)
                .allowsHitTesting(!hideTabBarForBrowse)
                .animation(.easeOut(duration: 0.22), value: hideTabBarForBrowse)
        }
        .background(canvas)
        .ignoresSafeArea(edges: .bottom)
        .onPreferenceChange(BrowseFullscreenKey.self) { hideTabBarForBrowse = $0 }
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
