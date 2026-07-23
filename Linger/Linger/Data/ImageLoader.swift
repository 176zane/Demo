import Photos
import UIKit

/// 单次图片请求的回调载荷（含 iCloud / 降级信息）
struct ImageLoadPayload: Sendable {
    let image: UIImage?
    let isDegraded: Bool
    let isInCloud: Bool
    let hasError: Bool

    /// 资源在库中找不到或系统报错
    var isUnavailable: Bool {
        hasError || image == nil && !isInCloud && !isDegraded
    }
}

/// PHCachingImageManager 封装：按需加载、可取消、支持预取
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let manager = PHCachingImageManager()
    private var requestIDs: [ObjectIdentifier: PHImageRequestID] = [:]

    private init() {
        manager.allowsCachingHighQualityImages = true
    }

    /// 为 SwiftUI 视图加载图片；token 用于取消（通常传视图 identity）
    @discardableResult
    func requestImage(
        for localIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        token: ObjectIdentifier,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID? {
        requestImage(
            for: localIdentifier,
            targetSize: targetSize,
            contentMode: contentMode,
            token: token
        ) { payload in
            completion(payload.image)
        }
    }

    /// 带 iCloud / 降级元数据的加载接口
    @discardableResult
    func requestImage(
        for localIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        token: ObjectIdentifier,
        onUpdate: @escaping (ImageLoadPayload) -> Void
    ) -> PHImageRequestID? {
        cancelRequest(for: token)

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            onUpdate(ImageLoadPayload(image: nil, isDegraded: false, isInCloud: false, hasError: true))
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        // 降级：iCloud 占位时先给低清，再尝试高清回调

        let requestID = manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }

            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            let hasError = info?[PHImageErrorKey] != nil
            let payload = ImageLoadPayload(
                image: image,
                isDegraded: degraded,
                isInCloud: inCloud,
                hasError: hasError || (image == nil && !inCloud)
            )

            DispatchQueue.main.async {
                onUpdate(payload)
            }
        }
        requestIDs[token] = requestID
        return requestID
    }

    func cancelRequest(for token: ObjectIdentifier) {
        if let id = requestIDs.removeValue(forKey: token) {
            manager.cancelImageRequest(id)
        }
    }

    /// 预取相邻资源，减少滑动卡顿
    func startCaching(identifiers: [String], targetSize: CGSize) {
        guard !identifiers.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var list: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        guard !list.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        manager.startCachingImages(
            for: list,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        )
    }

    func stopCaching(identifiers: [String], targetSize: CGSize) {
        guard !identifiers.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var list: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        manager.stopCachingImages(
            for: list,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: nil
        )
    }
}
