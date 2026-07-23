import Foundation
import SwiftUI

/// 应用级依赖与路由状态
@MainActor
final class AppState: ObservableObject {
    enum RootScreen: Equatable {
        case permission
        case review
    }

    let photoLibrary: PhotoLibraryServing
    let statsStore: StatsStore
    let preferencesStore: PreferencesStore

    @Published var rootScreen: RootScreen = .permission
    @Published var authStatus: PhotoAuthStatus = .notDetermined

    init(
        photoLibrary: PhotoLibraryServing? = nil,
        statsStore: StatsStore? = nil,
        preferencesStore: PreferencesStore? = nil
    ) {
        // 默认注入单例；测试可传入 mock
        self.photoLibrary = photoLibrary ?? PhotoLibraryService.shared
        self.statsStore = statsStore ?? StatsStore()
        self.preferencesStore = preferencesStore ?? PreferencesStore()
        refreshAuth()
    }

    func refreshAuth() {
        authStatus = photoLibrary.authorizationStatus()
        rootScreen = authStatus.canAccessLibrary ? .review : .permission
    }

    func requestAccess() async {
        authStatus = await photoLibrary.requestAuthorization()
        rootScreen = authStatus.canAccessLibrary ? .review : .permission
    }
}
