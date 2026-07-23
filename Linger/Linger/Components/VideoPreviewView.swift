import AVFoundation
import AVKit
import SwiftUI

/// 视频短预览：默认静音、循环前几秒，避免突然外放与冗长播放
struct VideoPreviewView: View {
    /// 短预览循环时长（秒）
    static let previewLoopSeconds: Double = 3

    let localIdentifier: String
    var onLoadStateChange: ((MediaLoadState) -> Void)? = nil

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var errorMessage: String?

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
                ProgressView().tint(.white)
            }

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
        .task(id: localIdentifier) {
            await load()
        }
        .onDisappear {
            player?.pause()
            looper = nil
            player = nil
        }
    }

    private func load() async {
        onLoadStateChange?(.loading)
        errorMessage = nil
        player?.pause()
        looper = nil
        player = nil
        do {
            let item = try await VideoLoader.loadPlayerItem(localIdentifier: localIdentifier)
            // 解析时长后裁剪为短预览区间；时长未知时默认 3 秒
            let assetDuration = try await item.asset.load(.duration)
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

            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            let playerLooper = AVPlayerLooper(
                player: queuePlayer,
                templateItem: item,
                timeRange: timeRange
            )
            looper = playerLooper
            player = queuePlayer
            queuePlayer.play()
            onLoadStateChange?(.ready)
        } catch {
            errorMessage = "视频加载失败"
            onLoadStateChange?(.failed)
        }
    }
}
