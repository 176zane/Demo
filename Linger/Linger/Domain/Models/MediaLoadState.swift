import Foundation

/// 浏览卡片媒体加载状态：用于 iCloud 占位 / 失败时展示「跳过」
enum MediaLoadState: Equatable, Sendable {
    /// 正在拉取（可能含 iCloud 下载）
    case loading
    /// 已有可展示内容（含低清占位）
    case ready
    /// iCloud 仍在下载，仅有低清或尚无图
    case waitingForCloud
    /// 资源不存在或最终加载失败，可跳过
    case failed
}
