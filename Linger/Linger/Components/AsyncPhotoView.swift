import Photos
import SwiftUI
import UIKit

/// 用于 ImageLoader 取消请求的稳定 token 持有者
@MainActor
final class ImageRequestToken: ObservableObject {
    private let anchor = NSObject()
    var id: ObjectIdentifier { ObjectIdentifier(anchor) }
}

/// 按 localIdentifier 异步加载并展示静态图
struct AsyncPhotoView: View {
    let localIdentifier: String
    var contentMode: ContentMode = .fit
    /// 是否铺一层占位底；详情页只要照片本身，关掉以免露出圆角底
    var showsPlaceholderCanvas: Bool = true
    /// 向父视图汇报加载状态（iCloud / 失败 → 可跳过）
    var onLoadStateChange: ((MediaLoadState) -> Void)? = nil

    @StateObject private var token = ImageRequestToken()
    @State private var image: UIImage?
    @State private var loadState: MediaLoadState = .loading
    /// iCloud 等待超时后仍无高清时，升级为可跳过提示
    @State private var cloudWaitTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showsPlaceholderCanvas {
                    Color.black.opacity(0.12)
                }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        // 不用 opacity 转场：父级英雄弹簧会把首次出图插成半透明叠影
                        .transition(.identity)
                } else if loadState == .failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("无法加载")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }

                // iCloud 下载中且仅有低清/无图时给出状态条（跳过按钮在浏览页统一提供）
                if loadState == .waitingForCloud {
                    VStack {
                        Spacer()
                        Label("iCloud 下载中…", systemImage: "icloud.and.arrow.down")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 16)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                request(size: CGSize(
                    width: max(geo.size.width, 1) * UIScreen.main.scale,
                    height: max(geo.size.height, 1) * UIScreen.main.scale
                ))
            }
            .onChange(of: localIdentifier) { _, _ in
                image = nil
                publish(.loading)
                request(size: CGSize(
                    width: max(geo.size.width, 1) * UIScreen.main.scale,
                    height: max(geo.size.height, 1) * UIScreen.main.scale
                ))
            }
            .onDisappear {
                cloudWaitTask?.cancel()
                ImageLoader.shared.cancelRequest(for: token.id)
            }
        }
    }

    private func request(size: CGSize) {
        cloudWaitTask?.cancel()
        publish(.loading)

        ImageLoader.shared.requestImage(
            for: localIdentifier,
            targetSize: size,
            token: token.id
        ) { payload in
            if let img = payload.image {
                withAnimation(.easeOut(duration: 0.2)) {
                    image = img
                }
            }

            if payload.hasError && payload.image == nil {
                publish(.failed)
                return
            }

            // 仅有低清且标记在云端：展示 waiting，并启动超时后仍可跳过
            if payload.isInCloud && (payload.image == nil || payload.isDegraded) {
                publish(.waitingForCloud)
                scheduleCloudTimeout()
                return
            }

            if payload.image != nil {
                cloudWaitTask?.cancel()
                publish(.ready)
            } else if image == nil {
                publish(.failed)
            }
        }
    }

    /// 云端下载过久仍无最终图：保持 waitingForCloud，由浏览页提供跳过
    private func scheduleCloudTimeout() {
        cloudWaitTask?.cancel()
        cloudWaitTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            // 超时后若仍无最终就绪，维持 waiting，父级已可跳过；若完全无图则标失败
            if image == nil {
                publish(.failed)
            } else if loadState == .waitingForCloud {
                onLoadStateChange?(.waitingForCloud)
            }
        }
    }

    private func publish(_ state: MediaLoadState) {
        loadState = state
        onLoadStateChange?(state)
    }
}
