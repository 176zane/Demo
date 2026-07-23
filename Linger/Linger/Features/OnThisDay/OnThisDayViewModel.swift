import Combine
import Foundation

/// 「那年今日」Stories 浏览状态
@MainActor
final class OnThisDayViewModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?
    @Published var isFavorite = false

    private let photoLibrary: PhotoLibraryServing
    private let allowedKinds: Set<MediaKind>

    init(photoLibrary: PhotoLibraryServing, allowedKinds: Set<MediaKind>) {
        self.photoLibrary = photoLibrary
        self.allowedKinds = allowedKinds
    }

    var currentItem: MediaItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    var progressCount: Int { items.count }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await photoLibrary.fetchOnThisDayItems(
                allowedKinds: allowedKinds,
                yearsBack: 12
            )
            index = 0
            isFavorite = currentItem?.isFavorite ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func advance() {
        guard !items.isEmpty else { return }
        index = min(index + 1, items.count - 1)
        isFavorite = currentItem?.isFavorite ?? false
    }

    func retreat() {
        guard !items.isEmpty else { return }
        index = max(index - 1, 0)
        isFavorite = currentItem?.isFavorite ?? false
    }

    /// 回到第一条（回放）
    func restart() {
        guard !items.isEmpty else { return }
        index = 0
        isFavorite = currentItem?.isFavorite ?? false
    }

    func toggleFavorite() async {
        guard let item = currentItem else { return }
        let next = !isFavorite
        do {
            try await photoLibrary.setFavorite(next, id: item.id)
            isFavorite = next
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
