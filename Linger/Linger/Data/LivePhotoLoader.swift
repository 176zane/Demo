import Photos
import UIKit

/// 实况照片加载
enum LivePhotoLoader {
    /// 异步请求 PHLivePhoto；失败返回 nil（调用方降级为静态图）
    static func load(
        localIdentifier: String,
        targetSize: CGSize
    ) async -> PHLivePhoto? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaSubtypes.contains(.photoLive) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            // 用原子标记避免 continuation 被 resume 两次
            let resumed = ResumeBox()
            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    resumed.resume(nil, continuation: continuation)
                    return
                }
                resumed.resume(livePhoto, continuation: continuation)
            }
        }
    }

    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resume(
            _ value: PHLivePhoto?,
            continuation: CheckedContinuation<PHLivePhoto?, Never>
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: value)
        }
    }
}
