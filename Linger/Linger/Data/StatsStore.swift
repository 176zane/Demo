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

    func recordViewed(_ count: Int = 1) {
        var next = stats
        next.recordViewed(count)
        stats = next
        persist()
    }

    func recordDeleted(_ count: Int = 1) {
        var next = stats
        next.recordDeleted(count)
        stats = next
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
