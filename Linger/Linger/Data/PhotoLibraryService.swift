import Foundation
import Photos

/// PhotoKit 实现：授权、随机抽组、按日查询、删除
@MainActor
final class PhotoLibraryService: PhotoLibraryServing {
    static let shared = PhotoLibraryService()

    /// 全库枚举阈值：超过后改用随机索引探测，避免一次性装入内存
    static let fullScanThreshold = 2_500
    /// 随机探测时，为目标数量准备的候选倍数
    private static let candidateMultiplier = 8

    private let recentStore: RecentViewedStore

    /// 自拍相簿 identifier 缓存，避免逐 asset 扫描
    private var selfieIDsCache: Set<String>?
    private var selfieCacheBuiltAt: Date?

    init(recentStore: RecentViewedStore? = nil) {
        // 默认参数不能直接构造 @MainActor 类型，故在 init 体内创建
        self.recentStore = recentStore ?? RecentViewedStore()
    }

    func authorizationStatus() -> PhotoAuthStatus {
        mapStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotoAuthStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return mapStatus(status)
    }

    func fetchRandomItems(
        count: Int,
        allowedKinds: Set<MediaKind>,
        excluding excludeIDs: Set<String>
    ) async throws -> [MediaItem] {
        try ensureAuthorized()
        let candidates = collectCandidates(
            count: count,
            allowedKinds: allowedKinds,
            excluding: excludeIDs
        )
        let sampled = RandomSampler.sample(
            from: candidates,
            count: count,
            excluding: excludeIDs,
            recentIDs: recentStore.ids
        )
        if sampled.isEmpty {
            throw PhotoLibraryError.emptyLibrary
        }
        recentStore.remember(sampled.map(\.id))
        return sampled
    }

    func fetchItems(on day: Date, allowedKinds: Set<MediaKind>) async throws -> [MediaItem] {
        try ensureAuthorized()

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw PhotoLibraryError.underlying("无法计算日期区间")
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            start as NSDate,
            end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let selfieIDs = selfieIdentifierSet()
        let fetchResult = PHAsset.fetchAssets(with: options)
        var items: [MediaItem] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if let item = Self.makeMediaItem(from: asset, selfieIDs: selfieIDs),
               allowedKinds.contains(item.mediaKind) {
                items.append(item)
            }
        }
        return items
    }

    func deleteAssets(withIDs ids: [String]) async throws -> DeleteResult {
        try ensureAuthorized()
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else {
            return DeleteResult(
                requestedIDs: [],
                deletedIDs: [],
                failedIDs: [],
                errorDescription: nil
            )
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uniqueIDs, options: nil)
        var toDelete: [PHAsset] = []
        var foundIDs: Set<String> = []
        assets.enumerateObjects { asset, _, _ in
            toDelete.append(asset)
            foundIDs.insert(asset.localIdentifier)
        }

        let missing = uniqueIDs.filter { !foundIDs.contains($0) }

        guard !toDelete.isEmpty else {
            return DeleteResult(
                requestedIDs: uniqueIDs,
                deletedIDs: [],
                failedIDs: uniqueIDs,
                errorDescription: "没有找到可删除的照片"
            )
        }

        do {
            try await performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
            }
            let deleted = toDelete.map(\.localIdentifier)
            return DeleteResult(
                requestedIDs: uniqueIDs,
                deletedIDs: deleted,
                failedIDs: missing,
                errorDescription: missing.isEmpty ? nil : "部分资源已不存在"
            )
        } catch {
            throw PhotoLibraryError.deleteFailed(error.localizedDescription)
        }
    }

    func hasAnyMedia(allowedKinds: Set<MediaKind>) async -> Bool {
        guard authorizationStatus().canAccessLibrary else { return false }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: options)
        guard fetchResult.count > 0 else { return false }

        let selfieIDs = selfieIdentifierSet()
        var found = false
        // 找到第一个匹配即停止，避免为探测构建完整数组
        fetchResult.enumerateObjects { asset, _, stop in
            if let item = Self.makeMediaItem(from: asset, selfieIDs: selfieIDs),
               allowedKinds.contains(item.mediaKind) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    func setFavorite(_ favorite: Bool, id: String) async throws {
        try ensureAuthorized()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else {
            throw PhotoLibraryError.assetNotFound(id)
        }
        try await performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = favorite
        }
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        guard authorizationStatus().canAccessLibrary else {
            throw PhotoLibraryError.notAuthorized
        }
    }

    /// 收集抽样候选：小库全量匹配；大库随机索引探测以控制内存
    private func collectCandidates(
        count: Int,
        allowedKinds: Set<MediaKind>,
        excluding excludeIDs: Set<String>
    ) -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: options)
        let total = fetchResult.count
        guard total > 0 else { return [] }

        let selfieIDs = selfieIdentifierSet()
        let targetPool = max(count * Self.candidateMultiplier, count)

        if total <= Self.fullScanThreshold {
            return enumerateAllMatching(
                fetchResult: fetchResult,
                allowedKinds: allowedKinds,
                selfieIDs: selfieIDs
            )
        }

        return sampleByRandomIndex(
            fetchResult: fetchResult,
            total: total,
            targetPool: targetPool,
            allowedKinds: allowedKinds,
            excluding: excludeIDs,
            selfieIDs: selfieIDs
        )
    }

    private func enumerateAllMatching(
        fetchResult: PHFetchResult<PHAsset>,
        allowedKinds: Set<MediaKind>,
        selfieIDs: Set<String>
    ) -> [MediaItem] {
        var items: [MediaItem] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if let item = Self.makeMediaItem(from: asset, selfieIDs: selfieIDs),
               allowedKinds.contains(item.mediaKind) {
                items.append(item)
            }
        }
        return items
    }

    /// 大相册：随机抽索引构建候选池，避免 O(n) 全量装载
    private func sampleByRandomIndex(
        fetchResult: PHFetchResult<PHAsset>,
        total: Int,
        targetPool: Int,
        allowedKinds: Set<MediaKind>,
        excluding excludeIDs: Set<String>,
        selfieIDs: Set<String>
    ) -> [MediaItem] {
        var picked: [MediaItem] = []
        var seenIndexes = Set<Int>()
        var seenIDs = Set<String>()
        // 限制尝试次数，防止筛选极严时空转
        let maxAttempts = min(total, max(targetPool * 6, 200))
        var attempts = 0

        while picked.count < targetPool && seenIndexes.count < total && attempts < maxAttempts {
            attempts += 1
            let index = Int.random(in: 0..<total)
            if !seenIndexes.insert(index).inserted { continue }

            let asset = fetchResult.object(at: index)
            guard let item = Self.makeMediaItem(from: asset, selfieIDs: selfieIDs),
                  allowedKinds.contains(item.mediaKind),
                  !excludeIDs.contains(item.id),
                  seenIDs.insert(item.id).inserted else {
                continue
            }
            picked.append(item)
        }
        return picked
    }

    /// 构建（并短时缓存）自拍智能相册中的 identifier 集合
    private func selfieIdentifierSet() -> Set<String> {
        if let cache = selfieIDsCache,
           let builtAt = selfieCacheBuiltAt,
           Date().timeIntervalSince(builtAt) < 60 {
            return cache
        }

        var ids = Set<String>()
        let selfies = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumSelfPortraits,
            options: nil
        )
        if let album = selfies.firstObject {
            let assets = PHAsset.fetchAssets(in: album, options: nil)
            assets.enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        selfieIDsCache = ids
        selfieCacheBuiltAt = Date()
        return ids
    }

    private func performChanges(_ block: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(block) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: PhotoLibraryError.deleteFailed("系统拒绝了删除请求"))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotoAuthStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    static func makeMediaItem(from asset: PHAsset, selfieIDs: Set<String>) -> MediaItem? {
        let kind = detectKind(for: asset, selfieIDs: selfieIDs)
        return MediaItem(
            id: asset.localIdentifier,
            mediaKind: kind,
            creationDate: asset.creationDate,
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    static func detectKind(for asset: PHAsset, selfieIDs: Set<String>) -> MediaKind {
        if asset.mediaType == .video {
            return .video
        }
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return .screenshot
        }
        if asset.mediaSubtypes.contains(.photoLive) {
            return .livePhoto
        }
        if isAnimatedGIF(asset) {
            return .gif
        }
        if selfieIDs.contains(asset.localIdentifier) {
            return .selfie
        }
        return .photo
    }

    private static func isAnimatedGIF(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.contains { resource in
            let uti = resource.uniformTypeIdentifier.lowercased()
            return uti.contains("gif") || resource.originalFilename.lowercased().hasSuffix(".gif")
        }
    }
}
