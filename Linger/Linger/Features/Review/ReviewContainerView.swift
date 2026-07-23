import SwiftUI

/// 组装回顾 / 确认删除 / 设置 / 回到那天
struct ReviewContainerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    var body: some View {
        ReviewScreen(
            photoLibrary: appState.photoLibrary,
            statsStore: statsStore,
            preferencesStore: preferencesStore
        )
        .environmentObject(appState)
        .environmentObject(statsStore)
        .environmentObject(preferencesStore)
    }
}

/// 持有 StateObject，保证 @Published 能驱动 UI
private struct ReviewScreen: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @StateObject private var viewModel: ReviewViewModel

    init(
        photoLibrary: PhotoLibraryServing,
        statsStore: StatsStore,
        preferencesStore: PreferencesStore
    ) {
        _viewModel = StateObject(
            wrappedValue: ReviewViewModel(
                photoLibrary: photoLibrary,
                statsStore: statsStore,
                preferencesStore: preferencesStore
            )
        )
    }

    var body: some View {
        ZStack {
            if viewModel.phase == .confirming {
                ConfirmDeleteView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ReviewView(viewModel: viewModel)
            }
        }
        .task {
            // 仅在首次 loading 且无内容时启动，避免设置页返回重复抽组
            if viewModel.phase == .loading && viewModel.deal.isEmpty {
                await viewModel.start()
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
                .environmentObject(statsStore)
                .environmentObject(preferencesStore)
                .environmentObject(appState)
        }
        .sheet(isPresented: $viewModel.showDayTimeline) {
            if let date = viewModel.currentItem?.creationDate {
                DayTimelineView(
                    day: date,
                    photoLibrary: appState.photoLibrary,
                    allowedKinds: preferencesStore.allowedKinds
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
    }
}
