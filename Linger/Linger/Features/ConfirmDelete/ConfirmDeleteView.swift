import SwiftUI

/// 组末批量确认删除
struct ConfirmDeleteView: View {
    @ObservedObject var viewModel: ReviewViewModel
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.deal.markedItems.isEmpty {
                    ContentUnavailableView(
                        "没有待删除的内容",
                        systemImage: "checkmark.circle",
                        description: Text("直接开始下一组回顾吧")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(viewModel.deal.markedItems) { item in
                                thumbnail(item)
                            }
                        }
                        .padding(16)
                    }

                    if let deleteError = viewModel.deleteError {
                        VStack(spacing: 4) {
                            Text(deleteError)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                            Text("可调整勾选后重试，或跳过进入下一组")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

                actionBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("确认删除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过") {
                        Task { await viewModel.skipConfirmAndContinue() }
                    }
                    .disabled(viewModel.isDeleting)
                }
            }
            .onAppear {
                syncSelectionWithMarkedItems()
            }
            // 部分删除失败后列表会收窄，同步默认勾选到仍需重试的项
            .onChange(of: viewModel.deal.markedForDeletion) { _, _ in
                syncSelectionWithMarkedItems()
            }
        }
    }

    /// 默认全选当前待删项（含重试场景）
    private func syncSelectionWithMarkedItems() {
        selectedIDs = Set(viewModel.deal.markedItems.map(\.id))
    }

    private func thumbnail(_ item: MediaItem) -> some View {
        let selected = selectedIDs.contains(item.id)
        return Button {
            if selected {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                AsyncPhotoView(localIdentifier: item.id, contentMode: .fill)
                    .frame(minHeight: 110)
                    .clipped()
                    .overlay {
                        if !selected {
                            Color.black.opacity(0.45)
                        }
                    }

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .white)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 主按钮文案：空选 / 首次确认 / 失败后重试
    private var primaryActionTitle: String {
        if selectedIDs.isEmpty {
            return "不删除，下一组"
        }
        if viewModel.deleteError != nil {
            return "重试删除"
        }
        return "确认删除"
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Text("将删除 \(selectedIDs.count) 项（可取消勾选）")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.confirmDeletion(selectedIDs: selectedIDs) }
            } label: {
                HStack {
                    if viewModel.isDeleting {
                        ProgressView().tint(.white)
                    }
                    Text(primaryActionTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedIDs.isEmpty ? Color.secondary : Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.isDeleting)
            .accessibilityLabel(primaryActionTitle)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}
