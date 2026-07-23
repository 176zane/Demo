import Foundation

/// 媒体类型：用于随机池筛选与 UI 角标展示
enum MediaKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case photo
    case livePhoto
    case screenshot
    case selfie
    case gif
    case video

    var id: String { rawValue }

    /// 设置页展示用中文名
    var displayName: String {
        switch self {
        case .photo: return "普通照片"
        case .livePhoto: return "实况照片"
        case .screenshot: return "截屏"
        case .selfie: return "自拍"
        case .gif: return "动图"
        case .video: return "视频"
        }
    }

    /// 默认开启的筛选集合（全部类型）
    static var allEnabled: Set<MediaKind> { Set(MediaKind.allCases) }

    /// 照片 Tab 可用类型（排除视频，视频走独立 Tab）
    static var nonVideoKinds: Set<MediaKind> {
        Set(MediaKind.allCases.filter { $0 != .video })
    }

    /// 映射到统计分桶
    var statsBucket: StatsBucket {
        switch self {
        case .screenshot:
            return .screenshot
        case .video:
            return .video
        case .photo, .livePhoto, .selfie, .gif:
            return .photo
        }
    }
}
