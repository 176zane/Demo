import AVFoundation
import Photos

/// 视频预览用 AVPlayerItem 加载
enum VideoLoader {
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
