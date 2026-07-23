import Foundation
import Photos

/// 删除前估算本地资源占用字节（PhotoKit）
enum AssetByteEstimator {
    /// PhotoKit 私有 KVC 键；先检查 selector 再读取，避免 NSUnknownKeyException
    private static let fileSizeSelector = Selector(("fileSize"))

    /// 根据 localIdentifier 累加关联资源的 fileSize。
    /// 找不到资源、资源列表为空、或任一资源无法读取 fileSize 时，整体返回 0（不做部分累加）。
    static func estimatedBytes(forLocalIdentifier localIdentifier: String) async -> Int64 {
        await Task.detached(priority: .utility) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = assets.firstObject else { return 0 }

            let resources = PHAssetResource.assetResources(for: asset)
            guard !resources.isEmpty else { return 0 }

            var total: Int64 = 0
            for resource in resources {
                // 任一资源读不到 fileSize → 整次估算失败，返回 0
                guard let size = fileSize(from: resource) else { return 0 }
                total += size
            }
            return total
        }.value
    }

    /// 安全读取 fileSize：不支持的键返回 nil
    private static func fileSize(from resource: PHAssetResource) -> Int64? {
        guard resource.responds(to: fileSizeSelector) else { return nil }
        guard let raw = resource.value(forKey: "fileSize") else { return nil }
        if let size = raw as? Int64 { return max(0, size) }
        if let size = raw as? Int { return Int64(max(0, size)) }
        if let size = raw as? NSNumber { return max(0, size.int64Value) }
        return nil
    }
}
