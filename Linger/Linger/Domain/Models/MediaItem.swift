import Foundation

/// 相册媒体的轻量元数据；不持有大图，仅用 localIdentifier 按需加载
struct MediaItem: Identifiable, Hashable, Sendable {
    /// 与 PHAsset.localIdentifier 一致，作为稳定主键
    let id: String
    let mediaKind: MediaKind
    let creationDate: Date?
    let isFavorite: Bool
    /// 像素尺寸，供预加载目标尺寸估算（可为空）
    let pixelWidth: Int
    let pixelHeight: Int

    var localIdentifier: String { id }

    init(
        id: String,
        mediaKind: MediaKind,
        creationDate: Date?,
        isFavorite: Bool = false,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.creationDate = creationDate
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
