import Foundation

/// 一组随机回顾会话（一手牌）
struct ReviewDeal: Equatable, Sendable {
    var items: [MediaItem]
    var currentIndex: Int
    /// 已标记待删的 localIdentifier
    var markedForDeletion: Set<String>

    init(items: [MediaItem], currentIndex: Int = 0, markedForDeletion: Set<String> = []) {
        self.items = items
        self.currentIndex = currentIndex
        self.markedForDeletion = markedForDeletion
    }

    var isEmpty: Bool { items.isEmpty }

    var currentItem: MediaItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    /// 本组进度文案用：1-based
    var progressText: String {
        guard !items.isEmpty else { return "0/0" }
        let current = min(currentIndex + 1, items.count)
        return "\(current)/\(items.count)"
    }

    var hasFinishedBrowsing: Bool {
        items.isEmpty || currentIndex >= items.count
    }

    var markedItems: [MediaItem] {
        items.filter { markedForDeletion.contains($0.id) }
    }

    /// 标记当前为删除并前进；若已越界则不再移动
    mutating func markCurrentForDeletion() {
        guard let item = currentItem else { return }
        markedForDeletion.insert(item.id)
        advance()
    }

    /// 保留当前并前进
    mutating func keepCurrentAndAdvance() {
        advance()
    }

    /// 撤销最近一次删除标记（用于短时 toast 撤销）
    mutating func unmarkDeletion(id: String) {
        markedForDeletion.remove(id)
    }

    /// 从本组移除已成功删除的资源，并清理对应删除标记
    mutating func removeItems(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        markedForDeletion.subtract(ids)
        // 确认阶段索引可能已越界；夹紧避免后续逻辑读到脏下标
        if currentIndex > items.count {
            currentIndex = items.count
        }
    }

    /// 将待删集合收窄为仍需重试的 identifier（部分删除失败后使用）
    mutating func retainMarkedForDeletion(ids: Set<String>) {
        markedForDeletion = markedForDeletion.intersection(ids)
    }

    private mutating func advance() {
        currentIndex += 1
    }
}
