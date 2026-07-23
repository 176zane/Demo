import SwiftUI

/// 3D 卡片堆：顶卡可拖拽，后两张作为透视预览
struct CardStackView<Content: View>: View {
    let items: [MediaItem]
    let currentIndex: Int
    let dragOffset: CGSize
    @ViewBuilder var content: (MediaItem) -> Content

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width - 28
            let cardHeight = geo.size.height * 0.72
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.48)

            ZStack {
                // 从后往前画：index+2、index+1、当前
                ForEach(previewOffsets.reversed(), id: \.self) { offset in
                    let index = currentIndex + offset
                    if items.indices.contains(index) {
                        let item = items[index]
                        cardLayer(
                            item: item,
                            offset: offset,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            isFront: offset == 0
                        )
                        .position(center)
                        .zIndex(Double(10 - offset))
                        .id("\(item.id)-\(offset)")
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// 最多展示当前 + 后两张
    private var previewOffsets: [Int] { [0, 1, 2] }

    @ViewBuilder
    private func cardLayer(
        item: MediaItem,
        offset: Int,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        isFront: Bool
    ) -> some View {
        let depth = CGFloat(offset)
        // 后层略缩小、下沉，营造堆叠透视
        let scale = 1.0 - depth * 0.045
        let ySink = depth * 18
        let rotateY = isFront ? Double(dragOffset.width / 18) : Double(-6 - depth * 4)
        let frontOffset = isFront ? dragOffset : .zero
        let opacity = isFront ? (1.0 - min(abs(dragOffset.height) / 400, 0.35)) : (0.92 - depth * 0.08)

        content(item)
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(scale)
            .offset(x: frontOffset.width, y: frontOffset.height + ySink)
            .rotation3DEffect(
                .degrees(rotateY),
                axis: (x: 0.05, y: 1, z: 0),
                perspective: 0.65
            )
            .opacity(opacity)
            .allowsHitTesting(isFront)
            .animation(.spring(response: 0.35, dampingFraction: 0.84), value: dragOffset)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: currentIndex)
    }
}
