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
                PhotoReviewView(viewModel: viewModel)
            }
        }
        .task {
            if viewModel.phase == .loading && viewModel.deal.isEmpty {
                await viewModel.start()
            }
        }
        // 设置里改筛选后重新抽组（照片 Tab）
        .onChange(of: preferencesStore.allowedKinds) { _, _ in
            Task { await viewModel.loadNextDeal() }
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
                    allowedKinds: preferencesStore.allowedKinds.intersection(MediaKind.nonVideoKinds)
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
    }
}
