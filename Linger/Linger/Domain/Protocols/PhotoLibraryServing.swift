import Foundation

/// 相册访问协议：便于单元测试 mock
protocol PhotoLibraryServing: AnyObject {
    /// 当前授权状态（同步读取）
    func authorizationStatus() -> PhotoAuthStatus

    /// 请求读写权限（删除需要 readWrite）
    func requestAuthorization() async -> PhotoAuthStatus

    /// 按筛选条件随机抽取最多 count 条，排除 excludeIDs
    func fetchRandomItems(
        count: Int,
        allowedKinds: Set<MediaKind>,
        excluding excludeIDs: Set<String>
    ) async throws -> [MediaItem]

    /// 按自然日获取当天媒体（「回到那天」）
    func fetchItems(on day: Date, allowedKinds: Set<MediaKind>) async throws -> [MediaItem]

    /// 删除指定 localIdentifier；返回部分成功结果
    func deleteAssets(withIDs ids: [String]) async throws -> DeleteResult

    /// 库中是否至少有一张可用媒体（在筛选条件下）
    func hasAnyMedia(allowedKinds: Set<MediaKind>) async -> Bool
}

enum PhotoLibraryError: LocalizedError, Equatable {
    case notAuthorized
    case emptyLibrary
    case assetNotFound(String)
    case deleteFailed(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "尚未获得相册访问权限"
        case .emptyLibrary:
            return "相册里暂时没有符合条件的内容"
        case .assetNotFound(let id):
            return "找不到媒体：\(id)"
        case .deleteFailed(let message):
            return "删除失败：\(message)"
        case .underlying(let message):
            return message
        }
    }
}
