import AVFoundation
import Photos
import SwiftUI

/// 视频 Tab：全屏播放 + 右侧操作栏（收藏 / 分享 / 删除 / 撤销）
struct VideoReviewView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore

    /// 当前是否为可见 Tab；离开时暂停播放，避免后台空转
    var isActive: Bool = true

    @StateObject private var viewModel: VideoReviewViewModel
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    /// 首帧后再挂播放器，避免点 Tab 当帧同步创建 AVPlayer 造成卡顿
    @State private var shouldAttachPlayer = false

    init(
        photoLibrary: PhotoLibraryServing,
        statsStore: StatsStore,
        preferencesStore: PreferencesStore,
        isActive: Bool = true
    ) {
        self.isActive = isActive
        _viewModel = StateObject(
            wrappedValue: VideoReviewViewModel(
                photoLibrary: photoLibrary,
                statsStore: statsStore,
                preferencesStore: preferencesStore
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ProgressView("抽取视频中…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .empty:
                emptyState
            case .error(let message):
                errorState(message)
            case .browsing:
                browsingContent
            }
        }
        .task {
            // 预挂载时即可后台抽组，不必等用户点进视频 Tab
            if viewModel.items.isEmpty {
                await viewModel.start()
            }
        }
        .task(id: isActive) {
            if isActive {
                // 让 Tab 切换先完成绘制，再挂 AVPlayer
                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
                shouldAttachPlayer = true
            } else {
                shouldAttachPlayer = false
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: shareItems)
        }
    }

    private var browsingContent: some View {
        ZStack {
            if let item = viewModel.currentItem {
                if isActive && shouldAttachPlayer {
                    VideoPreviewView(
                        localIdentifier: item.id,
                        loopShortPreview: false,
                        progress: Binding(
                            get: { viewModel.playbackProgress },
                            set: { viewModel.playbackProgress = $0 }
                        )
                    )
                    .ignoresSafeArea()
                    .id(item.id)
                } else {
                    // 占位：预热完成但未激活 / 等待首帧，保持黑底不闪白
                    Color.black.ignoresSafeArea()
                    if isActive {
                        ProgressView().tint(.white)
                    }
                }
            }

            // 右侧操作栏
            HStack {
                Spacer()
                VStack(spacing: 18) {
                    GlassCircleButton(systemName: viewModel.isFavorite ? "heart.fill" : "heart") {
                        Task { await viewModel.toggleFavorite() }
                    }
                    .foregroundStyle(viewModel.isFavorite ? LingerTheme.accentRed : .white)

                    GlassCircleButton(systemName: "square.and.arrow.up") {
                        Task { await shareCurrent() }
                    }

                    GlassCircleButton(systemName: "trash") {
                        Task { await viewModel.deleteCurrent() }
                    }

                    GlassCircleButton(systemName: "arrow.uturn.backward") {
                        if viewModel.showUndoToast {
                            viewModel.undoPendingDelete()
                        } else {
                            Task { await viewModel.keepAndAdvance() }
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 120)
            }

            VStack {
                Spacer()
                HStack {
                    Text(RelativeDateLabel.text(for: viewModel.currentItem?.creationDate))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 20)

                // 播放进度
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(4, geo.size.width * viewModel.playbackProgress))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 100)

                if viewModel.showUndoToast {
                    ToastBanner(message: "已移入删除队列", actionTitle: "撤销") {
                        viewModel.undoPendingDelete()
                    }
                    .padding(.bottom, 88)
                } else if let toast = viewModel.toastMessage {
                    ToastBanner(message: toast)
                        .padding(.bottom, 88)
                }
            }
        }
        // 左滑切下一条（保留）
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -80 {
                        Task { await viewModel.keepAndAdvance() }
                    }
                }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(LingerTheme.accentBlue)
            Text("暂时没有可回顾的视频")
                .foregroundStyle(.white)
            Button("再试一次") {
                Task { await viewModel.loadNextBatch() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 72)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("出了点问题")
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("重试") {
                Task { await viewModel.loadNextBatch() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 72)
    }

    /// 导出视频到临时文件后唤起系统分享
    private func shareCurrent() async {
        guard let id = viewModel.currentItem?.id else { return }
        do {
            let url = try await exportVideoURL(localIdentifier: id)
            shareItems = [url]
            showShareSheet = true
        } catch {
            viewModel.toastMessage = "分享失败：\(error.localizedDescription)"
        }
    }

    private func exportVideoURL(localIdentifier: String) async throws -> URL {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaType == .video else {
            throw PhotoLibraryError.assetNotFound(localIdentifier)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: PhotoLibraryError.underlying("无法导出视频"))
                    return
                }
                continuation.resume(returning: urlAsset.url)
            }
        }
    }
}

/// UIKit 分享面板包装
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
