import SwiftUI

/// 照片 Tab：回顾 / 组末确认 / 设置 / 回到那天
struct PhotoReviewContainerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    var body: some View {
        PhotoReviewScreen(
            photoLibrary: appState.photoLibrary,
            statsStore: statsStore,
            preferencesStore: preferencesStore
        )
        .environmentObject(appState)
        .environmentObject(statsStore)
        .environmentObject(preferencesStore)
    }
}

private struct PhotoReviewScreen: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @StateObject private var viewModel: PhotoReviewViewModel

    init(
        photoLibrary: PhotoLibraryServing,
        statsStore: StatsStore,
        preferencesStore: PreferencesStore
    ) {
        _viewModel = StateObject(
            wrappedValue: PhotoReviewViewModel(
                photoLibrary: photoLibrary,
                statsStore: statsStore,
                preferencesStore: preferencesStore,
                prefetcher: .shared
            )
        )
    }

    var body: some View {
        PhotoReviewView(viewModel: viewModel)
            .task {
                if viewModel.phase == .loading && viewModel.deal.isEmpty {
                    await viewModel.start()
                }
            }
            // 设置里改筛选或每组张数后重新抽组（预取器会按新配置重建队列）
            .onChange(of: preferencesStore.allowedKinds) { _, _ in
                Task { await viewModel.loadNextDeal() }
            }
            .onChange(of: preferencesStore.dealSize) { _, _ in
                Task { await viewModel.loadNextDeal() }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView()
                    .environmentObject(statsStore)
                    .environmentObject(preferencesStore)
                    .environmentObject(appState)
            }
            .fullScreenCover(isPresented: $viewModel.showOnThisDay) {
                OnThisDayView(
                    photoLibrary: appState.photoLibrary,
                    allowedKinds: preferencesStore.allowedKinds.intersection(MediaKind.nonVideoKinds),
                    onDismiss: { viewModel.showOnThisDay = false }
                )
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
    }
}
