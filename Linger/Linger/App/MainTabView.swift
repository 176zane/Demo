import SwiftUI

/// 权限通过后的主壳层，统一承载照片、视频和统计三个入口。
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @State private var selectedTab: MainTab = .photos

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $selectedTab)
                .padding(.bottom, 8)
        }
        .background(canvas)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .photos:
            PhotoReviewContainerView()
        case .videos:
            VideoReviewView(
                photoLibrary: appState.photoLibrary,
                statsStore: statsStore,
                preferencesStore: preferencesStore
            )
        case .stats:
            PlaceholderTabView(
                systemImage: "chart.bar.fill",
                title: "统计",
                message: "你的回顾成果会显示在这里"
            )
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

/// 后续任务接入正式页面前使用的轻量占位内容。
private struct PlaceholderTabView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LingerTheme.canvasTop, LingerTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(LingerTheme.accentBlue)

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.bottom, 72)
        }
        .accessibilityElement(children: .combine)
    }
}
