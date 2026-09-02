import Foundation
import ImageIO
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
        // 默认与统计重置共用 shared，避免清统计后抽组仍命中旧去重集
        self.recentStore = recentStore ?? RecentViewedStore.shared
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

        // 自拍集合仅在非「纯视频」池需要；视频 Tab 可跳过，减少首点卡顿
        let selfieIDs: Set<String> = (allowedKinds == [.video]) ? [] : selfieIdentifierSet()
        let recentSnapshot = recentStore.ids
        let want = count
        let kinds = allowedKinds
        let exclude = excludeIDs

        // PhotoKit 枚举放到后台，避免首次点视频 Tab 卡主线程
        let candidates = await Task.detached(priority: .userInitiated) {
            Self.collectCandidatesDetached(
                count: want,
                allowedKinds: kinds,
                excluding: exclude,
                selfieIDs: selfieIDs
            )
        }.value

        let sampled = RandomSampler.sample(
            from: candidates,
            count: count,
            excluding: excludeIDs,
            recentIDs: recentSnapshot
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
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        // 按 EXIF 朝向纠正宽高：侧向拍摄的竖图像素常是横的，不纠正会进错格子
        var items: [MediaItem] = []
        items.reserveCapacity(assets.count)
        for asset in assets {
            guard let base = Self.makeMediaItem(from: asset, selfieIDs: selfieIDs),
                  allowedKinds.contains(base.mediaKind) else {
                continue
            }
            items.append(await Self.itemWithOrientedPixels(base, asset: asset))
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

    func fetchOnThisDayItems(allowedKinds: Set<MediaKind>, yearsBack: Int) async throws -> [MediaItem] {
        try ensureAuthorized()
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let thisYear = calendar.component(.year, from: today)
        let selfieIDs = selfieIdentifierSet()

        var collected: [MediaItem] = []
        let span = max(1, yearsBack)
        for year in (thisYear - span)..<thisYear {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                continue
            }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate,
                end as NSDate
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(with: options)
            result.enumerateObjects { asset, _, _ in
                if let item = Self.makeMediaItem(from: asset, selfieIDs: selfieIDs),
                   allowedKinds.contains(item.mediaKind) {
                    collected.append(item)
                }
            }
        }
        return collected
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        guard authorizationStatus().canAccessLibrary else {
            throw PhotoLibraryError.notAuthorized
        }
    }

    /// 后台可调用的候选收集（纯 PhotoKit，不触碰 MainActor 状态）
    nonisolated private static func collectCandidatesDetached(
        count: Int,
        allowedKinds: Set<MediaKind>,
        excluding excludeIDs: Set<String>,
        selfieIDs: Set<String>
    ) -> [MediaItem] {
        let fetchResult = fetchResult(for: allowedKinds)
        let total = fetchResult.count
        guard total > 0 else { return [] }

        let targetPool = max(count * candidateMultiplier, count)

        if total <= fullScanThreshold {
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

    /// 按筛选收窄 PhotoKit 查询：纯视频 / 纯图片走 mediaType，显著快于全库扫描
    nonisolated private static func fetchResult(for allowedKinds: Set<MediaKind>) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if allowedKinds == [.video] {
            return PHAsset.fetchAssets(with: .video, options: options)
        }
        if !allowedKinds.contains(.video) {
            return PHAsset.fetchAssets(with: .image, options: options)
        }
        return PHAsset.fetchAssets(with: options)
    }

    nonisolated private static func enumerateAllMatching(
        fetchResult: PHFetchResult<PHAsset>,
        allowedKinds: Set<MediaKind>,
        selfieIDs: Set<String>
    ) -> [MediaItem] {
        var items: [MediaItem] = []
        fetchResult.enumerateObjects { asset, _, _ in
            if let item = makeMediaItem(from: asset, selfieIDs: selfieIDs),
               allowedKinds.contains(item.mediaKind) {
                items.append(item)
            }
        }
        return items
    }

    /// 大相册：随机抽索引构建候选池，避免 O(n) 全量装载
    nonisolated private static func sampleByRandomIndex(
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
        let maxAttempts = min(total, max(targetPool * 6, 200))
        var attempts = 0

        while picked.count < targetPool && seenIndexes.count < total && attempts < maxAttempts {
            attempts += 1
            let index = Int.random(in: 0..<total)
            if !seenIndexes.insert(index).inserted { continue }

            let asset = fetchResult.object(at: index)
            guard let item = makeMediaItem(from: asset, selfieIDs: selfieIDs),
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

    /// 读出朝向后，把侧向拍摄的宽高对调，供「回到那天」按横竖选格子
    nonisolated static func itemWithOrientedPixels(_ item: MediaItem, asset: PHAsset) async -> MediaItem {
        let orientation = await imageOrientation(for: asset)
        let oriented = DayGridLayout.orientedDimensions(
            pixelWidth: item.pixelWidth,
            pixelHeight: item.pixelHeight,
            orientation: orientation
        )
        return MediaItem(
            id: item.id,
            mediaKind: item.mediaKind,
            creationDate: item.creationDate,
            isFavorite: item.isFavorite,
            pixelWidth: oriented.width,
            pixelHeight: oriented.height
        )
    }

    nonisolated static func imageOrientation(for asset: PHAsset) async -> CGImagePropertyOrientation {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { _, _, orientation, info in
                if info?[PHImageCancelledKey] as? Bool == true {
                    continuation.resume(returning: .up)
                    return
                }
                continuation.resume(returning: orientation)
            }
        }
    }

    nonisolated static func makeMediaItem(from asset: PHAsset, selfieIDs: Set<String>) -> MediaItem? {
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

    nonisolated static func detectKind(for asset: PHAsset, selfieIDs: Set<String>) -> MediaKind {
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

    nonisolated private static func isAnimatedGIF(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.contains { resource in
            let uti = resource.uniformTypeIdentifier.lowercased()
            return uti.contains("gif") || resource.originalFilename.lowercased().hasSuffix(".gif")
        }
    }
}
