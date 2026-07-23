import Foundation

/// 相册授权状态的应用层抽象，避免 UI 直接依赖 Photos 枚举
enum PhotoAuthStatus: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited

    var canAccessLibrary: Bool {
        switch self {
        case .authorized, .limited:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        }
    }
}
