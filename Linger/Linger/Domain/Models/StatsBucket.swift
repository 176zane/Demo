import Foundation

/// 统计分桶：照片、截屏、视频
enum StatsBucket: String, CaseIterable, Codable, Hashable, Sendable {
    case photo
    case screenshot
    case video
}
