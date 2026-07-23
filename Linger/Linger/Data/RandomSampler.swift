import Foundation

/// 纯函数随机抽样：便于单测，不依赖 Photos
enum RandomSampler {
    /// 从 candidates 中随机取最多 count 个，排除 exclude，并用近期集合降低重复
    static func sample(
        from candidates: [MediaItem],
        count: Int,
        excluding excludeIDs: Set<String>,
        recentIDs: Set<String> = [],
        rng: inout some RandomNumberGenerator
    ) -> [MediaItem] {
        guard count > 0 else { return [] }

        // 优先从未看过的池子抽；不够再放宽到 recent
        let fresh = candidates.filter { !excludeIDs.contains($0.id) && !recentIDs.contains($0.id) }
        let fallback = candidates.filter { !excludeIDs.contains($0.id) && recentIDs.contains($0.id) }

        var pool = fresh
        if pool.count < count {
            pool.append(contentsOf: fallback)
        }

        guard !pool.isEmpty else { return [] }

        let shuffled = pool.shuffled(using: &rng)
        return Array(shuffled.prefix(count))
    }

    /// 使用系统随机源的便捷方法
    static func sample(
        from candidates: [MediaItem],
        count: Int,
        excluding excludeIDs: Set<String>,
        recentIDs: Set<String> = []
    ) -> [MediaItem] {
        var rng = SystemRandomNumberGenerator()
        return sample(
            from: candidates,
            count: count,
            excluding: excludeIDs,
            recentIDs: recentIDs,
            rng: &rng
        )
    }
}
