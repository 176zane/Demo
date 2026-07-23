import XCTest
@testable import Linger

@MainActor
final class MockPhotoLibraryTests: XCTestCase {
    func testFetchRandomUsesSamplerConstraints() async throws {
        let mock = MockPhotoLibrary()
        mock.items = (0..<30).map {
            MediaItem(id: "m-\($0)", mediaKind: .photo, creationDate: Date())
        }
        let result = try await mock.fetchRandomItems(
            count: 5,
            allowedKinds: [.photo],
            excluding: ["m-0"]
        )
        XCTAssertEqual(result.count, 5)
        XCTAssertFalse(result.contains(where: { $0.id == "m-0" }))
    }

    func testEmptyLibraryThrows() async {
        let mock = MockPhotoLibrary()
        mock.items = []
        do {
            _ = try await mock.fetchRandomItems(count: 10, allowedKinds: [.photo], excluding: [])
            XCTFail("应抛出 emptyLibrary")
        } catch let error as PhotoLibraryError {
            XCTAssertEqual(error, .emptyLibrary)
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
    }

    func testFetchItemsOnDayFiltersByDate() async throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let other = calendar.date(byAdding: .day, value: -3, to: day)!

        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "today", mediaKind: .photo, creationDate: day.addingTimeInterval(3600)),
            MediaItem(id: "other", mediaKind: .photo, creationDate: other)
        ]

        let result = try await mock.fetchItems(on: day, allowedKinds: [.photo])
        XCTAssertEqual(result.map(\.id), ["today"])
    }
}

@MainActor
final class MockPhotoLibrary: PhotoLibraryServing {
    var status: PhotoAuthStatus = .authorized
    var items: [MediaItem] = []
    var deleted: [String] = []
    /// deleteAssets 被调用次数（验证「标记≠删除」）
    var deleteCallCount = 0
    /// 若设置则优先返回该删除结果（用于部分失败测试）
    var deleteResultOverride: DeleteResult?
    /// 若设置则删除时抛出该错误
    var deleteShouldThrow: Error?

    func authorizationStatus() -> PhotoAuthStatus { status }

    func requestAuthorization() async -> PhotoAuthStatus { status }

    func fetchRandomItems(
        count: Int,
        allowedKinds: Set<MediaKind>,
        excluding excludeIDs: Set<String>
    ) async throws -> [MediaItem] {
        let filtered = items.filter { allowedKinds.contains($0.mediaKind) }
        let sampled = RandomSampler.sample(
            from: filtered,
            count: count,
            excluding: excludeIDs
        )
        if sampled.isEmpty { throw PhotoLibraryError.emptyLibrary }
        return sampled
    }

    func fetchItems(on day: Date, allowedKinds: Set<MediaKind>) async throws -> [MediaItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return items.filter { item in
            guard allowedKinds.contains(item.mediaKind),
                  let date = item.creationDate else { return false }
            return date >= start && date < end
        }
        .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
    }

    func deleteAssets(withIDs ids: [String]) async throws -> DeleteResult {
        deleteCallCount += 1
        if let deleteShouldThrow {
            throw deleteShouldThrow
        }
        deleted.append(contentsOf: ids)
        if let deleteResultOverride {
            return deleteResultOverride
        }
        return DeleteResult(
            requestedIDs: ids,
            deletedIDs: ids,
            failedIDs: [],
            errorDescription: nil
        )
    }

    func hasAnyMedia(allowedKinds: Set<MediaKind>) async -> Bool {
        items.contains { allowedKinds.contains($0.mediaKind) }
    }
}
