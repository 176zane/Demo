import SwiftUI

/// 回到那天：当天所有照片的滚动网格，捏合的那张高亮并居中
struct DayGridView: View {
    let day: Date
    let focusID: String
    let photoLibrary: PhotoLibraryServing
    let allowedKinds: Set<MediaKind>
    var onDismiss: () -> Void

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            background

            if isLoading {
                ProgressView("回到那天…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                gridContent
            }

            // 顶部日期 + 关闭
            VStack {
                HStack {
                    Text(day.formatted(date: .long, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    GlassCircleButton(systemName: "xmark") {
                        onDismiss()
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }
        }
        .task { await load() }
    }

    /// 深紫渐变背景（参照沉浸式回忆视觉）
    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.1, blue: 0.4),
                Color(red: 0.08, green: 0.04, blue: 0.16),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        gridCell(item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
                // 上下留白，保证首尾照片也能滚动到屏幕中央
                .padding(.vertical, 220)
            }
            .onAppear {
                // 等 LazyVGrid 估算完布局后再居中捏合的那张
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(focusID, anchor: .center)
                }
            }
        }
    }

    private func gridCell(_ item: MediaItem) -> some View {
        let isFocus = item.id == focusID
        return AsyncPhotoView(localIdentifier: item.id, contentMode: .fill)
            .frame(height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if isFocus {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2.5)
                }
            }
            .shadow(color: isFocus ? .black.opacity(0.5) : .clear, radius: 14, y: 8)
            .opacity(isFocus ? 1 : 0.55)
            .scaleEffect(isFocus ? 1.06 : 1)
            .zIndex(isFocus ? 1 : 0)
            .onTapGesture { onDismiss() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("返回") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await photoLibrary.fetchItems(on: day, allowedKinds: allowedKinds)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
