import Foundation

/// 批量删除结果：支持部分成功场景
struct DeleteResult: Equatable, Sendable {
    let requestedIDs: [String]
    let deletedIDs: [String]
    let failedIDs: [String]
    let errorDescription: String?

    var isFullySuccessful: Bool {
        failedIDs.isEmpty && errorDescription == nil
    }

    var deletedCount: Int { deletedIDs.count }
}
