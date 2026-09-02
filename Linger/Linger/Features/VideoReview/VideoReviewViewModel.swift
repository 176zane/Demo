import Foundation
import SwiftUI

/// 视频 Tab：全屏回顾；垃圾桶走「5 秒可撤销的延迟删除」（无确认页）
@MainActor
final class VideoReviewViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case browsing
        case empty
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isFavorite: Bool = false
    @Published var toastMessage: String?
    @Published var showUndoToast: Bool = false
    @Published var playbackProgress: Double = 0

    /// 撤销窗口（测试可缩短）
    var undoWindowNanoseconds: UInt64 = 5_000_000_000

    private let photoLibrary: PhotoLibraryServing
    private let statsStore: StatsStore
    private let preferencesStore: PreferencesStore
    private var pendingDeletes: [(item: MediaItem, bytes: Int64)] = []
    private var flushTask: Task<Void, Never>?
    private var viewedIDs: Set<String> = []

    init(
        photoLibrary: PhotoLibraryServing,
        statsStore: StatsStore,
        preferencesStore: PreferencesStore
    ) {
        self.photoLibrary = photoLibrary
        self.statsStore = statsStore
        self.preferencesStore = preferencesStore
    }

    var currentItem: MediaItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    func start() async {
        await loadNextBatch()
    }

    func loadNextBatch() async {
        // 先刷掉尚未提交的删除，避免切批后丢撤销语义
        await flushPendingDeletes()
        phase = .loading
        playbackProgress = 0
        do {
            let batch = try await photoLibrary.fetchRandomItems(
                count: preferencesStore.dealSize,
                allowedKinds: [.video],
                excluding: []
            )
            items = batch
            currentIndex = 0
            viewedIDs = []
            if let first = currentItem {
                recordView(first)
                isFavorite = first.isFavorite
                phase = .browsing
                // 后台预热当前 + 下一条播放器资源，进 Tab 即刻可播
                prewarmUpcoming()
            } else {
                phase = .empty
            }
        } catch let error as PhotoLibraryError {
            phase = error == .emptyLibrary ? .empty : .error(error.localizedDescription)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func keepAndAdvance() async {
        await flushPendingDeletes()
        advance()
    }

    /// 垃圾桶：进入待删队列 + 5 秒撤销窗，不立即 deleteAssets
    func deleteCurrent() async {
        guard phase == .browsing, let item = currentItem else { return }
        let bytes = await AssetByteEstimator.estimatedBytes(forLocalIdentifier: item.id)
        items.remove(at: currentIndex)
        if currentIndex >= items.count {
            currentIndex = max(0, items.count - 1)
        }
        pendingDeletes.append((item, bytes))
        showUndoToast = true
        toastMessage = nil
        scheduleFlush()

        if items.isEmpty {
            await loadNextBatch()
        } else if let next = currentItem {
            recordView(next)
            isFavorite = next.isFavorite
            playbackProgress = 0
            prewarmUpcoming()
        }
    }

    /// 撤销最近一次待删（仍在窗口内）
    func undoPendingDelete() {
        guard let last = pendingDeletes.popLast() else { return }
        flushTask?.cancel()
        flushTask = nil
        showUndoToast = false
        let insertAt = min(currentIndex, items.count)
        items.insert(last.item, at: insertAt)
        currentIndex = insertAt
        isFavorite = last.item.isFavorite
        toastMessage = "已撤销删除"
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if toastMessage == "已撤销删除" {
                toastMessage = nil
            }
        }
    }

    func toggleFavorite() async {
        guard let item = currentItem else { return }
        let next = !isFavorite
        do {
            try await photoLibrary.setFavorite(next, id: item.id)
            isFavorite = next
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                let old = items[index]
                items[index] = MediaItem(
                    id: old.id,
                    mediaKind: old.mediaKind,
                    creationDate: old.creationDate,
                    isFavorite: next,
                    pixelWidth: old.pixelWidth,
                    pixelHeight: old.pixelHeight
                )
            }
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    /// 供测试：立即刷待删队列
    func flushPendingDeletes() async {
        flushTask?.cancel()
        flushTask = nil
        showUndoToast = false
        guard !pendingDeletes.isEmpty else { return }
        let batch = pendingDeletes
        pendingDeletes = []
        let ids = batch.map(\.item.id)
        var bytesByID: [String: Int64] = [:]
        for entry in batch {
            bytesByID[entry.item.id] = entry.bytes
        }
        do {
            let result = try await photoLibrary.deleteAssets(withIDs: ids)
            if result.deletedCount > 0 {
                var totalBytes: Int64 = 0
                for id in result.deletedIDs {
                    totalBytes += bytesByID[id] ?? 0
                }
                statsStore.recordDeleted(bucket: .video, count: result.deletedCount, bytes: totalBytes)
            }
            if !result.failedIDs.isEmpty {
                toastMessage = result.errorDescription ?? "部分视频删除失败"
            }
        } catch {
            toastMessage = error.localizedDescription
            // 失败时把条目放回列表头部，避免静默丢失
            for entry in batch.reversed() {
                items.insert(entry.item, at: 0)
            }
            currentIndex = 0
        }
    }

    // MARK: - Private

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = undoWindowNanoseconds
        flushTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await flushPendingDeletes()
        }
    }

    private func advance() {
        guard phase == .browsing else { return }
        if currentIndex + 1 < items.count {
            currentIndex += 1
            if let item = currentItem {
                recordView(item)
                isFavorite = item.isFavorite
                playbackProgress = 0
                prewarmUpcoming()
            }
        } else {
            Task { await loadNextBatch() }
        }
    }

    /// 预热当前与下一条视频的 AVPlayerItem（当前条命中说明尚未播放过）
    private func prewarmUpcoming() {
        let candidates = [currentIndex, currentIndex + 1]
            .filter { items.indices.contains($0) }
            .map { items[$0].id }
        guard !candidates.isEmpty else { return }
        Task {
            for id in candidates {
                await VideoLoader.prewarm(localIdentifier: id)
            }
        }
    }

    private func recordView(_ item: MediaItem) {
        guard !viewedIDs.contains(item.id) else { return }
        viewedIDs.insert(item.id)
        statsStore.recordViewed(bucket: .video, count: 1)
    }
}
