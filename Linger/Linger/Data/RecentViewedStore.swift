import Foundation

/// 跨启动持久化「近期已看」identifier，降低短时间重复抽到同一批
@MainActor
final class RecentViewedStore {
    private enum Keys {
        static let ids = "linger.recentViewed.ids"
    }

    private let defaults: UserDefaults
    private let cap: Int
    private(set) var ids: Set<String>

    init(defaults: UserDefaults = .standard, cap: Int = 500) {
        self.defaults = defaults
        // 至少保留 1；测试可传入更小 cap 验证淘汰
        self.cap = max(cap, 1)
        if let stored = defaults.array(forKey: Keys.ids) as? [String] {
            // 保留写入顺序的尾部，便于超出上限时淘汰最旧项
            self.ids = Set(stored.suffix(self.cap))
            self.ordered = Array(stored.suffix(self.cap))
        } else {
            self.ids = []
            self.ordered = []
        }
    }

    /// 有序列表：旧 → 新，淘汰时从头部移除
    private var ordered: [String]

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// 记录一批刚抽到/看过的资源
    func remember(_ newIDs: [String]) {
        guard !newIDs.isEmpty else { return }
        for id in newIDs {
            if ids.contains(id) {
                // 移到末尾表示最近再次出现
                if let index = ordered.firstIndex(of: id) {
                    ordered.remove(at: index)
                }
            } else {
                ids.insert(id)
            }
            ordered.append(id)
        }
        trimIfNeeded()
        persist()
    }

    private func trimIfNeeded() {
        guard ordered.count > cap else { return }
        let overflow = ordered.count - cap
        // 先拷贝再截断，避免 ArraySlice 在 removeFirst 后指向错误元素
        let removed = Array(ordered.prefix(overflow))
        ordered.removeFirst(overflow)
        for id in removed {
            ids.remove(id)
        }
    }

    private func persist() {
        defaults.set(ordered, forKey: Keys.ids)
    }
}
