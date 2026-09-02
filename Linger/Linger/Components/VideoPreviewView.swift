import AVFoundation
import AVKit
import SwiftUI

/// 视频预览：短预览循环或全长播放（带进度回调）
struct VideoPreviewView: View {
    /// 短预览循环时长（秒）
    static let previewLoopSeconds: Double = 3

    let localIdentifier: String
    /// true：循环前几秒；false：完整播放并上报进度
    var loopShortPreview: Bool = true
    var onLoadStateChange: ((MediaLoadState) -> Void)? = nil
    var progress: Binding<Double>? = nil

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var errorMessage: String?
    @State private var timeObserver: Any?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .onAppear {
                        player.isMuted = true
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.8))
            } else {
                // 播放器就绪前先显示视频海报帧，消除黑屏等待感
                AsyncPhotoView(localIdentifier: localIdentifier, contentMode: .fit)
                ProgressView().tint(.white)
            }

            if loopShortPreview {
                VStack {
                    HStack {
                        Label("视频", systemImage: "video.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    .padding(16)
                    Spacer()
                }
            }
        }
        .task(id: localIdentifier) {
            await load()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func load() async {
        onLoadStateChange?(.loading)
        errorMessage = nil
        tearDownPlayer()
        do {
            // 优先用预热好的 item，首帧即刻可播
            let item: AVPlayerItem
            if let prewarmed = VideoLoader.takePrewarmed(localIdentifier: localIdentifier) {
                item = prewarmed
            } else {
                item = try await VideoLoader.loadPlayerItem(localIdentifier: localIdentifier)
            }
            let assetDuration = try await item.asset.load(.duration)
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true

            if loopShortPreview {
                let seconds: Double
                if assetDuration.isNumeric && assetDuration.seconds.isFinite && assetDuration.seconds > 0 {
                    seconds = min(Self.previewLoopSeconds, assetDuration.seconds)
                } else {
                    seconds = Self.previewLoopSeconds
                }
                let timeRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: seconds, preferredTimescale: 600)
                )
                looper = AVPlayerLooper(player: queuePlayer, templateItem: item, timeRange: timeRange)
            } else {
                // 全片循环 + 进度条
                looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
                attachProgressObserver(to: queuePlayer, duration: assetDuration)
            }

            player = queuePlayer
            queuePlayer.play()
            onLoadStateChange?(.ready)
        } catch {
            errorMessage = "视频加载失败"
            onLoadStateChange?(.failed)
        }
    }

    private func attachProgressObserver(to queuePlayer: AVQueuePlayer, duration: CMTime) {
        guard let progress, duration.isNumeric, duration.seconds > 0 else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = queuePlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let ratio = time.seconds / duration.seconds
            progress.wrappedValue = min(1, max(0, ratio))
        }
    }

    private func tearDownPlayer() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        player?.pause()
        looper = nil
        player = nil
    }
}
