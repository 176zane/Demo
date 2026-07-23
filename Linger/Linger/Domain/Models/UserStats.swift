import Foundation

/// 用户成就统计（done-list），持久化到 UserDefaults
struct UserStats: Codable, Equatable, Sendable {
    var viewedCount: Int
    var deletedCount: Int

    static let empty = UserStats(viewedCount: 0, deletedCount: 0)

    /// 增加浏览计数，带下限保护避免异常负值写入
    mutating func recordViewed(_ count: Int = 1) {
        viewedCount = max(0, viewedCount + max(0, count))
    }

    /// 增加删除计数
    mutating func recordDeleted(_ count: Int = 1) {
        deletedCount = max(0, deletedCount + max(0, count))
    }
}
