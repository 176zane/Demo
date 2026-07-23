import Foundation

/// 持久化浏览/删除统计
@MainActor
final class StatsStore: ObservableObject {
    private enum Keys {
        static let stats = "linger.stats"
    }

    private let defaults: UserDefaults

    @Published private(set) var stats: UserStats

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.stats),
           let decoded = try? JSONDecoder().decode(UserStats.self, from: data) {
            self.stats = decoded
        } else {
            self.stats = .empty
        }
    }

    /// 按分桶记录浏览
    func recordViewed(bucket: StatsBucket, count: Int = 1) {
        var next = stats
        next.recordViewed(bucket: bucket, count: count)
        stats = next
        persist()
    }

    /// 按分桶记录删除及释放字节
    func recordDeleted(bucket: StatsBucket, count: Int = 1, bytes: Int64 = 0) {
        var next = stats
        next.recordDeleted(bucket: bucket, count: count, freedBytes: bytes)
        stats = next
        persist()
    }

    /// 兼容旧调用：未指定桶时归入照片桶
    func recordViewed(_ count: Int = 1) {
        recordViewed(bucket: .photo, count: count)
    }

    /// 兼容旧调用：未指定桶时归入照片桶
    func recordDeleted(_ count: Int = 1) {
        recordDeleted(bucket: .photo, count: count)
    }

    /// 清空全部统计（RecentViewedStore 由调用方另行重置）
    func resetAll() {
        stats = .empty
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(stats)
            defaults.set(data, forKey: Keys.stats)
        } catch {
            // 统计写入失败不应阻断主流程，仅打印便于调试
            print("[StatsStore] persist failed: \(error.localizedDescription)")
        }
    }
}
