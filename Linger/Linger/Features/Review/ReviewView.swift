import SwiftUI

/// 回顾主界面：卡片 + 手势 + 进度
struct ReviewView: View {
    @ObservedObject var viewModel: ReviewViewModel

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
                // 由容器切换到确认页
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
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.10),
                Color(red: 0.10, green: 0.14, blue: 0.16)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Text("Linger")
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var browsingContent: some View {
        GeometryReader { geo in
            if let item = viewModel.currentItem {
                MediaCardView(item: item) { state in
                    viewModel.updateMediaLoadState(state)
                }
                    .frame(width: geo.size.width - 28, height: geo.size.height * 0.72)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.48)
                    .offset(viewModel.dragOffset)
                    .rotationEffect(.degrees(Double(viewModel.dragOffset.width / 20)))
                    .opacity(1.0 - min(abs(viewModel.dragOffset.height) / 400, 0.35))
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .animation(.spring(response: 0.35, dampingFraction: 0.84), value: viewModel.dragOffset)
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 90)
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
                    .accessibilityLabel("跳过当前媒体")
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
                .padding(.bottom, 18)
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
                // 捏合缩小（双指捏合）进入「回到那天」
                if value < 0.85 {
                    viewModel.openDayTimeline()
                }
            }
    }
}
