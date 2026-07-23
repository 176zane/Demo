import Foundation

/// 用户成就统计（done-list），持久化到 UserDefaults
struct UserStats: Codable, Equatable, Sendable {
    var viewedByBucket: [StatsBucket: Int]
    var deletedByBucket: [StatsBucket: Int]
    var freedBytesByBucket: [StatsBucket: Int64]

    /// 全部桶的浏览总数
    var viewedCount: Int {
        viewedByBucket.values.reduce(0, +)
    }

    /// 全部桶的删除总数
    var deletedCount: Int {
        deletedByBucket.values.reduce(0, +)
    }

    /// 全部桶释放的字节总和
    var totalFreedBytes: Int64 {
        freedBytesByBucket.values.reduce(0, +)
    }

    static let empty = UserStats(
        viewedByBucket: [:],
        deletedByBucket: [:],
        freedBytesByBucket: [:]
    )

    /// 按分桶累加浏览计数，带下限保护避免异常负值写入
    mutating func recordViewed(bucket: StatsBucket, count: Int = 1) {
        let delta = max(0, count)
        guard delta > 0 else { return }
        viewedByBucket[bucket, default: 0] = max(0, (viewedByBucket[bucket] ?? 0) + delta)
    }

    /// 按分桶累加删除计数与释放字节
    mutating func recordDeleted(bucket: StatsBucket, count: Int = 1, freedBytes: Int64 = 0) {
        let delta = max(0, count)
        guard delta > 0 else { return }
        deletedByBucket[bucket, default: 0] = max(0, (deletedByBucket[bucket] ?? 0) + delta)
        if freedBytes > 0 {
            freedBytesByBucket[bucket, default: 0] += freedBytes
        }
    }

    /// 重置为初始空状态
    mutating func reset() {
        self = .empty
    }

    /// 兼容旧 API：未指定桶时归入照片桶
    mutating func recordViewed(_ count: Int = 1) {
        recordViewed(bucket: .photo, count: count)
    }

    /// 兼容旧 API：未指定桶时归入照片桶
    mutating func recordDeleted(_ count: Int = 1) {
        recordDeleted(bucket: .photo, count: count)
    }

    // MARK: - Codable（兼容旧版 viewedCount / deletedCount 键）

    private enum CodingKeys: String, CodingKey {
        case viewedByBucket
        case deletedByBucket
        case freedBytesByBucket
        case viewedCount
        case deletedCount
    }

    init(
        viewedByBucket: [StatsBucket: Int],
        deletedByBucket: [StatsBucket: Int],
        freedBytesByBucket: [StatsBucket: Int64]
    ) {
        self.viewedByBucket = viewedByBucket
        self.deletedByBucket = deletedByBucket
        self.freedBytesByBucket = freedBytesByBucket
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let buckets = try container.decodeIfPresent([StatsBucket: Int].self, forKey: .viewedByBucket) {
            viewedByBucket = buckets
        } else if let legacyViewed = try container.decodeIfPresent(Int.self, forKey: .viewedCount), legacyViewed > 0 {
            // 旧数据迁移：历史总数归入照片桶
            viewedByBucket = [.photo: legacyViewed]
        } else {
            viewedByBucket = [:]
        }

        if let buckets = try container.decodeIfPresent([StatsBucket: Int].self, forKey: .deletedByBucket) {
            deletedByBucket = buckets
        } else if let legacyDeleted = try container.decodeIfPresent(Int.self, forKey: .deletedCount), legacyDeleted > 0 {
            deletedByBucket = [.photo: legacyDeleted]
        } else {
            deletedByBucket = [:]
        }

        freedBytesByBucket = try container.decodeIfPresent([StatsBucket: Int64].self, forKey: .freedBytesByBucket) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(viewedByBucket, forKey: .viewedByBucket)
        try container.encode(deletedByBucket, forKey: .deletedByBucket)
        try container.encode(freedBytesByBucket, forKey: .freedBytesByBucket)
    }
}
