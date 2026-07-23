import Foundation

/// 用户偏好：每组数量、启用的媒体类型筛选
@MainActor
final class PreferencesStore: ObservableObject {
    private enum Keys {
        static let dealSize = "linger.preferences.dealSize"
        static let allowedKinds = "linger.preferences.allowedKinds"
    }

    private let defaults: UserDefaults

    @Published var dealSize: Int {
        didSet {
            // 仅允许计划约定的档位，防止脏数据
            let clamped = Self.allowedDealSizes.contains(dealSize) ? dealSize : 20
            if clamped != dealSize {
                dealSize = clamped
                return
            }
            defaults.set(dealSize, forKey: Keys.dealSize)
        }
    }

    @Published var allowedKinds: Set<MediaKind> {
        didSet {
            let raw = allowedKinds.map(\.rawValue).sorted()
            defaults.set(raw, forKey: Keys.allowedKinds)
        }
    }

    static let allowedDealSizes = [10, 20, 30]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSize = defaults.object(forKey: Keys.dealSize) as? Int ?? 20
        self.dealSize = Self.allowedDealSizes.contains(storedSize) ? storedSize : 20

        if let raw = defaults.array(forKey: Keys.allowedKinds) as? [String] {
            let kinds = Set(raw.compactMap(MediaKind.init(rawValue:)))
            self.allowedKinds = kinds.isEmpty ? MediaKind.allEnabled : kinds
        } else {
            self.allowedKinds = MediaKind.allEnabled
        }
    }

    func toggleKind(_ kind: MediaKind) {
        // 至少保留一种类型，避免抽组永远为空
        if allowedKinds.contains(kind) {
            guard allowedKinds.count > 1 else { return }
            allowedKinds.remove(kind)
        } else {
            allowedKinds.insert(kind)
        }
    }
}
