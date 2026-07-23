import SwiftUI

/// 腾出空间的三段进度条（照片 / 截屏 / 视频）
struct SegmentedStorageBar: View {
    /// 各桶字节占比，和可为 0（显示空条）
    let fractions: [StatsBucket: Double]

    private let order: [StatsBucket] = [.photo, .screenshot, .video]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if totalFraction <= 0 {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: geo.size.width)
                } else {
                    ForEach(order, id: \.self) { bucket in
                        let width = max(0, geo.size.width * CGFloat(fractions[bucket] ?? 0))
                        if width > 0.5 {
                            Capsule()
                                .fill(color(for: bucket))
                                .frame(width: width)
                        }
                    }
                }
            }
        }
        .frame(height: 10)
    }

    private var totalFraction: Double {
        fractions.values.reduce(0, +)
    }

    private func color(for bucket: StatsBucket) -> Color {
        switch bucket {
        case .photo: return LingerTheme.accentBlue
        case .screenshot: return LingerTheme.accentRed
        case .video: return LingerTheme.accentGreen
        }
    }
}
