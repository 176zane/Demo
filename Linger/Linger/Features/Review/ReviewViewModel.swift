import Foundation
import SwiftUI
import UIKit

/// 随机回顾主流程状态机
@MainActor
final class ReviewViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case browsing
        case confirming
        case empty
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var deal: ReviewDeal = ReviewDeal(items: [])
    @Published var showDayTimeline = false
    @Published var showSettings = false
    @Published var undoBannerID: String?
    @Published var dragOffset: CGSize = .zero
    @Published var isDeleting = false
    @Published var deleteError: String?
    @Published var toastMessage: String?
    /// 当前卡片媒体加载状态（失败 / iCloud 等待时可跳过）
    @Published private(set) var mediaLoadState: MediaLoadState = .loading

    private let photoLibrary: PhotoLibraryServing
    private let statsStore: StatsStore
    private let preferencesStore: PreferencesStore
    private var undoTask: Task<Void, Never>?
    private var viewedInDeal: Set<String> = []

    /// 加载失败或 iCloud 久等时，浏览页展示「跳过」
    var canSkipUnavailableMedia: Bool {
        phase == .browsing && (mediaLoadState == .failed || mediaLoadState == .waitingForCloud)
    }

    init(
        photoLibrary: PhotoLibraryServing,
        statsStore: StatsStore,
        preferencesStore: PreferencesStore
    ) {
        self.photoLibrary = photoLibrary
        self.statsStore = statsStore
        self.preferencesStore = preferencesStore
    }

    var currentItem: MediaItem? { deal.currentItem }

    func start() async {
        await loadNextDeal()
    }

    /// 仅供单元测试注入确认态会话
    func applyTestingState(deal: ReviewDeal, phase: Phase) {
        self.deal = deal
        self.phase = phase
        self.deleteError = nil
    }

    func loadNextDeal() async {
        phase = .loading
        deleteError = nil
        mediaLoadState = .loading
        viewedInDeal = []

        // 照片 Tab：只抽非视频类型（与偏好筛选取交集）
        let kinds = activePhotoKinds
        let hasMedia = await photoLibrary.hasAnyMedia(allowedKinds: kinds)
        guard hasMedia else {
            phase = .empty
            return
        }

        do {
            let items = try await photoLibrary.fetchRandomItems(
                count: preferencesStore.dealSize,
                allowedKinds: kinds,
                excluding: []
            )
            deal = ReviewDeal(items: items)
            if let first = deal.currentItem {
                recordViewIfNeeded(first)
            }
            phase = .browsing
            prefetchNeighbors()
        } catch let error as PhotoLibraryError {
            if error == .emptyLibrary {
                phase = .empty
            } else {
                phase = .error(error.localizedDescription)
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func updateMediaLoadState(_ state: MediaLoadState) {
        mediaLoadState = state
    }

    /// 跳过无法加载 / iCloud 卡住的当前项（等同保留并前进）
    func skipUnavailableCurrent() {
        guard canSkipUnavailableMedia else { return }
        toastMessage = mediaLoadState == .waitingForCloud ? "已跳过 iCloud 资源" : "已跳过无法加载的资源"
        keepCurrent()
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if toastMessage == "已跳过 iCloud 资源" || toastMessage == "已跳过无法加载的资源" {
                toastMessage = nil
            }
        }
    }

    /// 上划：标记删除
    func markDeleteCurrent() {
        guard phase == .browsing, let item = deal.currentItem else { return }
        deal.markCurrentForDeletion()
        dragOffset = .zero
        mediaLoadState = .loading
        presentUndo(for: item.id)
        advanceAfterAction()
    }

    /// 保留并下一张
    func keepCurrent() {
        guard phase == .browsing, deal.currentItem != nil else { return }
        deal.keepCurrentAndAdvance()
        dragOffset = .zero
        mediaLoadState = .loading
        clearUndo()
        advanceAfterAction()
    }

    func undoMarkDeletion() {
        guard let id = undoBannerID else { return }
        deal.unmarkDeletion(id: id)
        toastMessage = "已撤销删除标记"
        clearUndo()
        // 短暂展示 toast
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if toastMessage == "已撤销删除标记" {
                toastMessage = nil
            }
        }
    }

    func openDayTimeline() {
        guard currentItem?.creationDate != nil else {
            toastMessage = "这张照片没有拍摄日期"
            return
        }
        showDayTimeline = true
    }

    /// 确认页：用户可取消勾选后提交
    func beginConfirmIfNeeded() {
        if deal.markedForDeletion.isEmpty {
            // 没有标记删除则直接下一组
            Task { await loadNextDeal() }
        } else {
            phase = .confirming
        }
    }

    func confirmDeletion(selectedIDs: Set<String>) async {
        // 用户取消全部勾选：不删除，直接进入下一组
        guard !selectedIDs.isEmpty else {
            deleteError = nil
            await loadNextDeal()
            return
        }

        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        do {
            // 删除前按项估算字节，成功后再写入对应分桶
            var bytesByID: [String: Int64] = [:]
            for id in selectedIDs {
                bytesByID[id] = await AssetByteEstimator.estimatedBytes(forLocalIdentifier: id)
            }

            let result = try await photoLibrary.deleteAssets(withIDs: Array(selectedIDs))
            if result.deletedCount > 0 {
                recordDeletedStats(forIDs: result.deletedIDs, bytesByID: bytesByID)
                // 已删成功的项从本组移除，确认页只保留失败项供重试
                deal.removeItems(ids: Set(result.deletedIDs))
            }

            if !result.failedIDs.isEmpty {
                deal.retainMarkedForDeletion(ids: Set(result.failedIDs))
                deleteError = result.errorDescription ?? "部分照片删除失败，可重试"
                toastMessage = deleteError
                phase = .confirming
                // 若失败项也已不在列表中，则无法重试，继续下一组
                if deal.markedItems.isEmpty {
                    await loadNextDeal()
                }
            } else {
                toastMessage = result.deletedCount > 0 ? "已删除 \(result.deletedCount) 项" : "未删除任何内容"
                await loadNextDeal()
            }
        } catch {
            // 整批失败：留在确认页，保留勾选以便用户重试
            deleteError = error.localizedDescription
            toastMessage = deleteError
            phase = .confirming
        }
    }

    func skipConfirmAndContinue() async {
        await loadNextDeal()
    }

    // MARK: - Private

    private func advanceAfterAction() {
        if deal.hasFinishedBrowsing {
            clearUndo()
            beginConfirmIfNeeded()
        } else if let item = deal.currentItem {
            recordViewIfNeeded(item)
            prefetchNeighbors()
        }
    }

    /// 照片池：偏好 ∩ 非视频；若交集为空则回退到全部非视频
    private var activePhotoKinds: Set<MediaKind> {
        let filtered = preferencesStore.allowedKinds.intersection(MediaKind.nonVideoKinds)
        return filtered.isEmpty ? MediaKind.nonVideoKinds : filtered
    }

    private func recordViewIfNeeded(_ item: MediaItem) {
        guard !viewedInDeal.contains(item.id) else { return }
        viewedInDeal.insert(item.id)
        statsStore.recordViewed(bucket: item.mediaKind.statsBucket, count: 1)
    }

    /// 按媒体类型分桶累计删除数与释放字节
    private func recordDeletedStats(forIDs ids: [String], bytesByID: [String: Int64]) {
        var tallies: [StatsBucket: (count: Int, bytes: Int64)] = [:]
        for id in ids {
            let kind = deal.items.first(where: { $0.id == id })?.mediaKind
                ?? deal.markedItems.first(where: { $0.id == id })?.mediaKind
                ?? .photo
            let bucket = kind.statsBucket
            let prev = tallies[bucket] ?? (0, 0)
            tallies[bucket] = (prev.count + 1, prev.bytes + (bytesByID[id] ?? 0))
        }
        for (bucket, tally) in tallies {
            statsStore.recordDeleted(bucket: bucket, count: tally.count, bytes: tally.bytes)
        }
    }

    private func presentUndo(for id: String) {
        undoBannerID = id
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            if undoBannerID == id {
                undoBannerID = nil
            }
        }
    }

    private func clearUndo() {
        undoTask?.cancel()
        undoBannerID = nil
    }

    private func prefetchNeighbors() {
        let ids = neighborIdentifiers()
        let size = CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale,
                          height: UIScreen.main.bounds.height * UIScreen.main.scale)
        ImageLoader.shared.startCaching(identifiers: ids, targetSize: size)
    }

    private func neighborIdentifiers() -> [String] {
        guard !deal.items.isEmpty else { return [] }
        var ids: [String] = []
        for offset in 0...2 {
            let index = deal.currentIndex + offset
            if deal.items.indices.contains(index) {
                ids.append(deal.items[index].id)
            }
        }
        return ids
    }
}
