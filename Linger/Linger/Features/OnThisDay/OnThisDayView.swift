import SwiftUI

/// 「那年今日」Stories：顶部分段进度 + 实况/照片浏览
struct OnThisDayView: View {
    @StateObject private var viewModel: OnThisDayViewModel
    var onDismiss: () -> Void

    init(photoLibrary: PhotoLibraryServing, allowedKinds: Set<MediaKind>, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(
            wrappedValue: OnThisDayViewModel(photoLibrary: photoLibrary, allowedKinds: allowedKinds)
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            LingerTheme.canvasBottom.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView().tint(.white)
            } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.white)
                    Button("关闭", action: onDismiss)
                }
            } else if viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    Text("暂无那年今日的回忆")
                        .foregroundStyle(.white)
                    Button("关闭", action: onDismiss)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                storiesBody
            }
        }
        .task { await viewModel.load() }
    }

    private var storiesBody: some View {
        VStack(spacing: 12) {
            // 顶部分段进度
            HStack(spacing: 4) {
                ForEach(0..<viewModel.progressCount, id: \.self) { i in
                    Capsule()
                        .fill(i <= viewModel.index ? Color.white : Color.white.opacity(0.25))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack {
                GlassCircleButton(systemName: "chevron.left", action: onDismiss)
                Spacer()
                GlassCircleButton(systemName: "square.and.arrow.up") {}
                    .opacity(0.35)
                    .disabled(true)
            }
            .padding(.horizontal, 16)

            if let item = viewModel.currentItem {
                MediaCardView(item: item)
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                    .id(item.id)
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                if value.translation.width < -40 {
                                    viewModel.advance()
                                } else if value.translation.width > 40 {
                                    viewModel.retreat()
                                }
                            }
                    )
            }

            HStack {
                GlassCircleButton(systemName: viewModel.isFavorite ? "heart.fill" : "heart") {
                    Task { await viewModel.toggleFavorite() }
                }
                Spacer()
                Text(RelativeDateLabel.text(for: viewModel.currentItem?.creationDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                GlassCircleButton(systemName: "arrow.counterclockwise") {
                    viewModel.restart()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}
