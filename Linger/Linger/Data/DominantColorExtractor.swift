import CoreImage
import Photos
import SwiftUI
import UIKit

/// 提取照片主色调并生成页面渐变背景
enum DominantColorExtractor {
    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    /// 主色缓存：同一张照片转场 / 翻页不再重复取色
    private static let cacheLock = NSLock()
    private static var colorCache: [String: UIColor] = [:]

    /// 按 localIdentifier 加载小缩略图并计算平均主色；失败返回 nil
    static func dominantColor(forLocalIdentifier id: String) async -> UIColor? {
        cacheLock.lock()
        let cached = colorCache[id]
        cacheLock.unlock()
        if let cached {
            return cached
        }

        guard let image = await thumbnail(forLocalIdentifier: id),
              let color = averageColor(of: image) else {
            return nil
        }
        cacheLock.lock()
        colorCache[id] = color
        cacheLock.unlock()
        return color
    }

    /// 直接给出上浅下深渐变；取色失败返回 nil
    static func gradient(forLocalIdentifier id: String) async -> (top: Color, bottom: Color)? {
        guard let base = await dominantColor(forLocalIdentifier: id) else { return nil }
        return gradientColors(from: base)
    }

    /// 同步读缓存，供转场 withAnimation 块内立刻对齐渐变
    static func cachedGradient(forLocalIdentifier id: String) -> (top: Color, bottom: Color)? {
        cacheLock.lock()
        let cached = colorCache[id]
        cacheLock.unlock()
        guard let cached else { return nil }
        return gradientColors(from: cached)
    }

    /// 由主色生成上浅下深的两段渐变色
    static func gradientColors(from base: UIColor) -> (top: Color, bottom: Color) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // 上端保留色相、略提亮；下端大幅压暗，保证前景可读
        let top = UIColor(
            hue: hue,
            saturation: min(1, saturation * 0.85),
            brightness: min(0.72, max(0.4, brightness * 1.05)),
            alpha: 1
        )
        let bottom = UIColor(
            hue: hue,
            saturation: min(1, saturation * 1.1),
            brightness: max(0.1, brightness * 0.3),
            alpha: 1
        )
        return (Color(top), Color(bottom))
    }

    /// CIAreaAverage 求整图平均色
    static func averageColor(of image: UIImage) -> UIColor? {
        guard let input = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent)
            ]
        ), let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }

    /// 拉取 64pt 缩略图用于取色（fastFormat 单次回调）
    private static func thumbnail(forLocalIdentifier id: String) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            // opportunistic：低清缩略图立刻回调，取色够用（fastFormat 在部分环境会报错）
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            let box = ResumeOnceBox()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 64, height: 64),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let image {
                    box.resume(continuation, with: image)
                    return
                }
                // 无图时：报错或非 iCloud 等待 → 直接失败；iCloud 下载中则等下次回调
                let hasError = info?[PHImageErrorKey] != nil
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if hasError || !inCloud {
                    box.resume(continuation, with: nil)
                }
            }
        }
    }

    /// 防御性单次 resume（PHImageManager 某些配置会多次回调）
    private final class ResumeOnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resume(_ continuation: CheckedContinuation<UIImage?, Never>, with image: UIImage?) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: image)
        }
    }
}
