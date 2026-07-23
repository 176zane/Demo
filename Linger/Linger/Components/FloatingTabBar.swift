import SwiftUI

/// 应用主导航的三个固定入口。
enum MainTab: Hashable, CaseIterable {
    case photos
    case videos
    case stats

    /// 面向用户展示的中文标题。
    var title: String {
        switch self {
        case .photos:
            return "照片"
        case .videos:
            return "视频"
        case .stats:
            return "统计"
        }
    }

    /// 与页面语义一致的 SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .photos:
            return "photo.on.rectangle.angled"
        case .videos:
            return "play.rectangle.fill"
        case .stats:
            return "chart.bar.fill"
        }
    }
}

/// 悬浮在主内容上方的玻璃胶囊导航栏。
struct FloatingTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.34), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
        .padding(.horizontal, 20)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.58))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selection == tab {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
