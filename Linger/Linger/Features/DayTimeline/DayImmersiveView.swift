import SwiftUI

/// 「回到那天」沉浸式横向浏览（紫黑渐变 + 大圆角焦点卡）
struct DayImmersiveView: View {
    let day: Date
    let photoLibrary: PhotoLibraryServing
    let allowedKinds: Set<MediaKind>
    var onDismiss: () -> Void

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedID: String?

    private var dayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: day)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.12, blue: 0.42),
                    LingerTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
                bottomBar
            }
        }
        .task { await reload() }
    }

    private var header: some View {
        HStack {
            GlassCircleButton(systemName: "chevron.left", action: onDismiss)
            Spacer()
            VStack(spacing: 2) {
                Text("回到那天")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(dayText)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Spacer()
            GlassCircleButton(systemName: "checkmark", action: onDismiss)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if let errorMessage {
            Spacer()
            Text(errorMessage)
                .foregroundStyle(.white.opacity(0.8))
                .padding()
            Spacer()
        } else if items.isEmpty {
            Spacer()
            ContentUnavailableView("这一天没有内容", systemImage: "photo")
                .foregroundStyle(.white)
            Spacer()
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        MediaCardView(item: item)
                            .frame(width: UIScreen.main.bounds.width * 0.78, height: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 28)
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(maxHeight: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack {
            GlassCircleButton(systemName: "arrow.clockwise") {
                Task { await reload() }
            }
            Spacer()
            GlassCircleButton(systemName: "arrow.uturn.backward", action: onDismiss)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await photoLibrary.fetchItems(on: day, allowedKinds: allowedKinds)
            selectedID = items.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
