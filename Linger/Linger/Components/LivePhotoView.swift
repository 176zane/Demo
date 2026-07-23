import Photos
import PhotosUI
import SwiftUI

/// PHLivePhotoView 的 SwiftUI 包装
struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    var isMuted: Bool = true

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.isMuted = isMuted
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        uiView.isMuted = isMuted
        // 进入时自动轻播一次，贴近原版「刷到实况」的感觉
        uiView.startPlayback(with: .hint)
    }
}

/// 加载并展示实况；失败时降级为静态图
struct LivePhotoContainer: View {
    let item: MediaItem
    var onLoadStateChange: ((MediaLoadState) -> Void)? = nil

    @State private var livePhoto: PHLivePhoto?
    @State private var loadFailed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let livePhoto {
                    LivePhotoRepresentable(livePhoto: livePhoto)
                        .transition(.opacity)
                } else if loadFailed {
                    // 实况失败时降级静态图，并继续汇报静态图加载状态
                    AsyncPhotoView(
                        localIdentifier: item.id,
                        onLoadStateChange: onLoadStateChange
                    )
                } else {
                    AsyncPhotoView(localIdentifier: item.id)
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .task(id: item.id) {
                loadFailed = false
                livePhoto = nil
                onLoadStateChange?(.loading)
                let size = CGSize(
                    width: max(geo.size.width, 1) * UIScreen.main.scale,
                    height: max(geo.size.height, 1) * UIScreen.main.scale
                )
                let result = await LivePhotoLoader.load(
                    localIdentifier: item.id,
                    targetSize: size
                )
                if let result {
                    withAnimation(.easeOut(duration: 0.25)) {
                        livePhoto = result
                    }
                    onLoadStateChange?(.ready)
                } else {
                    loadFailed = true
                    // 降级路径由 AsyncPhotoView 继续更新状态
                }
            }
        }
    }
}
