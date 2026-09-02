import SwiftUI

/// 统一媒体卡片：按类型分发静态图 / 实况 / 视频 / 动图
struct MediaCardView: View {
    let item: MediaItem
    /// 向回顾页汇报加载状态，便于展示「跳过」
    var onLoadStateChange: ((MediaLoadState) -> Void)? = nil
    /// 详情页关闭占位底，只保留媒体本身
    var showsPlaceholderCanvas: Bool = true
    /// 媒体在卡片内的缩放方式；详情页用 fill 铺满按比例算出的框
    var contentMode: ContentMode = .fit

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch item.mediaKind {
                case .video:
                    VideoPreviewView(
                        localIdentifier: item.id,
                        onLoadStateChange: onLoadStateChange
                    )
                case .livePhoto:
                    LivePhotoContainer(
                        item: item,
                        onLoadStateChange: onLoadStateChange
                    )
                case .gif:
                    GifPhotoView(
                        localIdentifier: item.id,
                        onLoadStateChange: onLoadStateChange
                    )
                default:
                    AsyncPhotoView(
                        localIdentifier: item.id,
                        contentMode: contentMode,
                        showsPlaceholderCanvas: showsPlaceholderCanvas,
                        onLoadStateChange: onLoadStateChange
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            kindBadge
                .padding(14)
        }
        .onAppear {
            // 切换卡片时重置为 loading，避免沿用上一张的失败态
            onLoadStateChange?(.loading)
        }
        .onChange(of: item.id) { _, _ in
            onLoadStateChange?(.loading)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        if item.mediaKind != .photo {
            Text(item.mediaKind.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}
