import Foundation
import Photos

/// 删除前估算本地资源占用字节（PhotoKit）
enum AssetByteEstimator {
    /// 根据 localIdentifier 累加关联资源的 fileSize；失败或找不到资源时返回 0
    static func estimatedBytes(forLocalIdentifier localIdentifier: String) async -> Int64 {
        await Task.detached(priority: .utility) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = assets.firstObject else { return 0 }

            let resources = PHAssetResource.assetResources(for: asset)
            guard !resources.isEmpty else { return 0 }

            var total: Int64 = 0
            for resource in resources {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    total += max(0, size)
                } else if let size = resource.value(forKey: "fileSize") as? Int {
                    total += Int64(max(0, size))
                } else if let size = resource.value(forKey: "fileSize") as? NSNumber {
                    total += size.int64Value
                }
            }
            return total
        }.value
    }
}
