import SwiftUI

/// 照片 Tab：3D 卡片堆 + 组末确认删除（复用 ReviewViewModel）
typealias PhotoReviewViewModel = ReviewViewModel

/// 照片回顾主界面
struct PhotoReviewView: View {
    @ObservedObject var viewModel: PhotoReviewViewModel
    @EnvironmentObject private var preferencesStore: PreferencesStore

    var body: some View {
        ZStack {
            background

            switch viewModel.phase {
            case .loading:
                ProgressView("抽取回忆中…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .empty:
                emptyState
            case .error(let message):
                errorState(message)
            case .browsing:
                browsingContent
            case .confirming:
                Color.clear
            }

            VStack {
                topBar
                Spacer()
                bottomChrome
            }
        }
        .statusBarHidden(viewModel.phase == .browsing)
    }

    private var background: some View {
        LinearGradient(
            colors: [LingerTheme.canvasTop, LingerTheme.canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            // 左上角筛选胶囊：照片池数量 + 类型开关（不含视频）
            Menu {
                ForEach(MediaKind.nonVideoKinds.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { kind in
                    Button {
                        preferencesStore.toggleKind(kind)
                    } label: {
                        HStack {
                            Text(kind.displayName)
                            if preferencesStore.allowedKinds.contains(kind) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("照片")
                        .font(.subheadline.weight(.semibold))
                    Text("\(remainingInDeal)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.18), in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .background(LingerTheme.glassFill, in: Capsule())
            }
            .accessibilityLabel("照片筛选")

            Spacer()

            GlassCircleButton(systemName: "gearshape") {
                viewModel.showSettings = true
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// 本组剩余未浏览张数（含当前）
    private var remainingInDeal: Int {
        guard !viewModel.deal.items.isEmpty else { return preferencesStore.dealSize }
        return max(0, viewModel.deal.items.count - viewModel.deal.currentIndex)
    }

    private var browsingContent: some View {
        CardStackView(
            items: viewModel.deal.items,
            currentIndex: viewModel.deal.currentIndex,
            dragOffset: viewModel.dragOffset
        ) { item in
            MediaCardView(item: item) { state in
                // 仅顶卡状态驱动跳过按钮
                if item.id == viewModel.currentItem?.id {
                    viewModel.updateMediaLoadState(state)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
        }
        .gesture(dragGesture)
        .gesture(magnificationGesture)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 12) {
            if let undoID = viewModel.undoBannerID {
                ToastBanner(message: "已标记删除", actionTitle: "撤销") {
                    viewModel.undoMarkDeletion()
                    _ = undoID
                }
            } else if let toast = viewModel.toastMessage {
                ToastBanner(message: toast)
            }

            if viewModel.phase == .browsing {
                if viewModel.canSkipUnavailableMedia {
                    Button {
                        viewModel.skipUnavailableCurrent()
                    } label: {
                        Text(viewModel.mediaLoadState == .waitingForCloud ? "跳过此张（iCloud）" : "跳过无法加载的内容")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.14), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                }

                HStack {
                    Text(viewModel.deal.progressText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("上划删除 · 左滑跳过 · 捏合回到那天")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 88)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text("没有符合筛选条件的内容")
                .foregroundStyle(.white)
            Text("可以在设置里调整类型筛选")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Button("打开设置") { viewModel.showSettings = true }
                .buttonStyle(.borderedProminent)
            Button("再试一次") {
                Task { await viewModel.loadNextDeal() }
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 72)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("出了点问题")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("重试") {
                Task { await viewModel.loadNextDeal() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 72)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.dragOffset = value.translation
            }
            .onEnded { value in
                let up = value.translation.height < -120
                let left = value.translation.width < -120
                if up {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.dragOffset = CGSize(width: 0, height: -560)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        viewModel.markDeleteCurrent()
                    }
                } else if left {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.dragOffset = CGSize(width: -420, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        viewModel.keepCurrent()
                    }
                } else {
                    withAnimation(.spring) {
                        viewModel.dragOffset = .zero
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                if value < 0.85 {
                    viewModel.openDayTimeline()
                }
            }
    }
}
