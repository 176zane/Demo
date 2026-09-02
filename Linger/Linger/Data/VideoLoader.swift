import AVFoundation
import Photos

/// 视频预览用 AVPlayerItem 加载
enum VideoLoader {
    /// 预热缓存：后台提前解析好的 AVPlayerItem（一个 item 只能被一个播放器使用，取走即移除）
    @MainActor
    private static var prewarmed: [String: AVPlayerItem] = [:]
    /// 预热缓存上限，防止占用过多内存
    private static let prewarmLimit = 3

    /// 后台预热：切 Tab / 播放下一条前调用，首帧无需等待 PhotoKit 解析
    @MainActor
    static func prewarm(localIdentifier: String) async {
        guard prewarmed[localIdentifier] == nil else { return }
        guard let item = try? await loadPlayerItem(localIdentifier: localIdentifier) else { return }
        if prewarmed.count >= prewarmLimit {
            prewarmed.removeAll()
        }
        prewarmed[localIdentifier] = item
        // 顺带把时长解析掉，播放路径直接命中缓存
        _ = try? await item.asset.load(.duration)
    }

    /// 取走预热好的 item（取走后失效）
    @MainActor
    static func takePrewarmed(localIdentifier: String) -> AVPlayerItem? {
        prewarmed.removeValue(forKey: localIdentifier)
    }

    /// 请求可播放的 AVPlayerItem；iCloud 资源允许网络下载
    static func loadPlayerItem(localIdentifier: String) async throws -> AVPlayerItem {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaType == .video else {
            throw PhotoLibraryError.assetNotFound(localIdentifier)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic

            let box = ThrowResumeBox<AVPlayerItem>()
            PHImageManager.default().requestPlayerItem(
                forVideo: asset,
                options: options
            ) { playerItem, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    box.resume(throwing: error, continuation: continuation)
                    return
                }
                guard let playerItem else {
                    box.resume(
                        throwing: PhotoLibraryError.underlying("无法加载视频预览"),
                        continuation: continuation
                    )
                    return
                }
                box.resume(returning: playerItem, continuation: continuation)
            }
        }
    }

    private final class ThrowResumeBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resume(
            returning value: T,
            continuation: CheckedContinuation<T, Error>
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: value)
        }

        func resume(
            throwing error: Error,
            continuation: CheckedContinuation<T, Error>
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(throwing: error)
        }
    }
}
