import SwiftUI

/// 「回到那天」：展示拍摄日当天的全部媒体
struct DayTimelineView: View {
    let day: Date
    let photoLibrary: PhotoLibraryServing
    let allowedKinds: Set<MediaKind>

    @Environment(\.dismiss) private var dismiss
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: MediaItem?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载当天回忆…")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "这天没有照片",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("试试别的筛选条件，或换一张有日期的照片")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(items) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    AsyncPhotoView(localIdentifier: item.id, contentMode: .fill)
                                        .frame(minHeight: 120)
                                        .clipped()
                                        .overlay(alignment: .bottomLeading) {
                                            if item.mediaKind == .video {
                                                Image(systemName: "video.fill")
                                                    .font(.caption2)
                                                    .padding(6)
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await load()
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    MediaCardView(item: item)
                        .padding()
                        .navigationTitle(item.mediaKind.displayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { selectedItem = nil }
                            }
                        }
                }
            }
        }
    }

    private var titleText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: day)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await photoLibrary.fetchItems(on: day, allowedKinds: allowedKinds)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
