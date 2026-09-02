import Foundation
import Photos
import UIKit

/// 抽组预取器：后台预抽若干组照片，打开照片页时零等待取用。
/// 队列持久化到 UserDefaults，下次启动可直接恢复继续使用。
@MainActor
final class DealPrefetcher {
    static let shared = DealPrefetcher()

    /// 预取队列目标长度（组数）
    private let targetDeals = 2
    private static let storageKey = "linger.prefetch.deals.v1"

    private var queue: [[MediaItem]] = []
    private var keySize = 0
    private var keyKinds: Set<MediaKind> = []
    private var refillTask: Task<Void, Never>?
    private var didRestore = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 取出一组；配置（张数 / 类型筛选）与预取时不一致或队列为空则返回 nil
    func takeDeal(size: Int, kinds: Set<MediaKind>) -> [MediaItem]? {
        restoreIfNeeded()
        guard size == keySize, kinds == keyKinds, !queue.isEmpty else { return nil }
        let deal = queue.removeFirst()
        persist()
        return deal
    }

    /// 后台补齐队列到目标组数；配置变化时丢弃旧缓存重新预取
    func ensureFilled(size: Int, kinds: Set<MediaKind>, photoLibrary: PhotoLibraryServing) {
        restoreIfNeeded()
        if size != keySize || kinds != keyKinds {
            queue = []
            keySize = size
            keyKinds = kinds
            persist()
        }
        guard queue.count < targetDeals, refillTask == nil else { return }

        refillTask = Task {
            defer { refillTask = nil }
            while queue.count < targetDeals, !Task.isCancelled {
                // 显式排除队列中已有的 id，保证各组互不重复
                let queuedIDs = Set(queue.flatMap { $0.map(\.id) })
                guard let items = try? await photoLibrary.fetchRandomItems(
                    count: size,
                    allowedKinds: kinds,
                    excluding: queuedIDs
                ), !items.isEmpty else {
                    break
                }
                // 补取期间配置可能已变化，丢弃过期结果
                guard size == keySize, kinds == keyKinds else { break }
                queue.append(items)
                preheatThumbnails(for: items)
            }
            persist()
        }
    }

    /// 清空缓存（如用户重置统计 / 去重记录后调用）
    func invalidate() {
        refillTask?.cancel()
        refillTask = nil
        queue = []
        persist()
    }

    /// 供测试观察队列长度
    var cachedDealCount: Int { queue.count }

    /// 供测试：等待后台补取任务结束
    func waitForRefill() async {
        await refillTask?.value
    }

    // MARK: - 缩略图预热

    /// 预热首页扇形三张的大图 + 整组小缩略图，进组即显示
    private func preheatThumbnails(for items: [MediaItem]) {
        let scale = UIScreen.main.scale
        let cardSize = CGSize(
            width: UIScreen.main.bounds.width * 0.6 * scale,
            height: UIScreen.main.bounds.width * 0.8 * scale
        )
        ImageLoader.shared.startCaching(
            identifiers: Array(items.prefix(3).map(\.id)),
            targetSize: cardSize
        )
    }

    // MARK: - 持久化

    private struct PersistedItem: Codable {
        var id: String
        var kind: MediaKind
        var creationDate: Date?
        var isFavorite: Bool
        var pixelWidth: Int
        var pixelHeight: Int
    }

    private struct PersistedState: Codable {
        var size: Int
        var kinds: Set<MediaKind>
        var deals: [[PersistedItem]]
    }

    private func persist() {
        let state = PersistedState(
            size: keySize,
            kinds: keyKinds,
            deals: queue.map { deal in
                deal.map {
                    PersistedItem(
                        id: $0.id,
                        kind: $0.mediaKind,
                        creationDate: $0.creationDate,
                        isFavorite: $0.isFavorite,
                        pixelWidth: $0.pixelWidth,
                        pixelHeight: $0.pixelHeight
                    )
                }
            }
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// 启动后首次访问时从磁盘恢复队列，并剔除已不存在的资源
    private func restoreIfNeeded() {
        guard !didRestore else { return }
        didRestore = true

        guard let data = defaults.data(forKey: Self.storageKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              !state.deals.isEmpty else {
            return
        }

        keySize = state.size
        keyKinds = state.kinds

        // 校验资源仍存在（可能已在系统相册中被删除）
        let allIDs = state.deals.flatMap { $0.map(\.id) }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)
        var existing = Set<String>()
        fetched.enumerateObjects { asset, _, _ in
            existing.insert(asset.localIdentifier)
        }

        queue = state.deals.compactMap { deal in
            let valid = deal.filter { existing.contains($0.id) }
            guard !valid.isEmpty else { return nil }
            return valid.map {
                MediaItem(
                    id: $0.id,
                    mediaKind: $0.kind,
                    creationDate: $0.creationDate,
                    isFavorite: $0.isFavorite,
                    pixelWidth: $0.pixelWidth,
                    pixelHeight: $0.pixelHeight
                )
            }
        }

        if let first = queue.first {
            preheatThumbnails(for: first)
        }
    }
}
