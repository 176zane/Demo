import ImageIO
import Photos
import SwiftUI
import UIKit

/// 动图（GIF）播放：从 PhotoKit 拉原始数据并解码为 animated UIImage
struct GifPhotoView: View {
    let localIdentifier: String
    var onLoadStateChange: ((MediaLoadState) -> Void)? = nil

    @State private var animatedImage: UIImage?
    @State private var loadState: MediaLoadState = .loading

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.12)
                if let animatedImage {
                    // UIImageView 才能正确播放多帧 GIF；SwiftUI Image 只会显示首帧
                    AnimatedImageRepresentable(image: animatedImage, contentMode: .scaleAspectFit)
                } else if loadState == .failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("动图加载失败")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: localIdentifier) {
                await load()
            }
        }
    }

    private func load() async {
        publish(.loading)
        animatedImage = nil
        do {
            let data = try await Self.requestGIFData(localIdentifier: localIdentifier)
            if let image = Self.makeAnimatedImage(from: data) {
                animatedImage = image
                publish(.ready)
            } else {
                // 解码失败时降级为静态帧展示
                publish(.failed)
            }
        } catch {
            publish(.failed)
        }
    }

    private func publish(_ state: MediaLoadState) {
        loadState = state
        onLoadStateChange?(state)
    }

    /// 请求原始图像数据（允许 iCloud）
    private static func requestGIFData(localIdentifier: String) async throws -> Data {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw PhotoLibraryError.assetNotFound(localIdentifier)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .original

            let box = ResumeBox()
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    box.resume(throwing: error, continuation: continuation)
                    return
                }
                guard let data else {
                    box.resume(
                        throwing: PhotoLibraryError.underlying("无法加载动图数据"),
                        continuation: continuation
                    )
                    return
                }
                box.resume(returning: data, continuation: continuation)
            }
        }
    }

    /// 使用 ImageIO 解码多帧 GIF
    private static func makeAnimatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        var duration: Double = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source: source, index: index)
        }

        guard !frames.isEmpty else { return nil }
        if duration <= 0 {
            duration = Double(frames.count) * 0.1
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        // 优先未钳制延时，其次常规延时
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return delay
        }
        return 0.1
    }

    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resume(returning value: Data, continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: value)
        }

        func resume(throwing error: Error, continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(throwing: error)
        }
    }
}

/// UIKit 包装：确保 animated UIImage 能播放，并撑满 SwiftUI 分配的尺寸
private struct AnimatedImageRepresentable: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.image = image
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.imageView = imageView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.imageView?.contentMode = contentMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var imageView: UIImageView?
    }
}
