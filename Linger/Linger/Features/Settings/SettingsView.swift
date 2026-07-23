import Photos
import PhotosUI
import SwiftUI
import UIKit

/// 设置：统计、每组数量、类型筛选、关于
struct SettingsView: View {
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("成就") {
                    HStack {
                        Label("已浏览", systemImage: "eye")
                        Spacer()
                        Text("\(statsStore.stats.viewedCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Label("已删除", systemImage: "trash")
                        Spacer()
                        Text("\(statsStore.stats.deletedCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("每组数量") {
                    Picker("每组", selection: $preferencesStore.dealSize) {
                        ForEach(PreferencesStore.allowedDealSizes, id: \.self) { size in
                            Text("\(size) 张").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(MediaKind.allCases) { kind in
                        Toggle(isOn: Binding(
                            get: { preferencesStore.allowedKinds.contains(kind) },
                            set: { _ in preferencesStore.toggleKind(kind) }
                        )) {
                            Text(kind.displayName)
                        }
                    }
                } header: {
                    Text("类型筛选")
                } footer: {
                    Text("至少保留一种类型。仅在你授权的相册范围内随机抽取。若使用「选中的照片」，只能访问已授权子集。")
                }

                Section("权限") {
                    HStack {
                        Text("相册权限")
                        Spacer()
                        Text(authText)
                            .foregroundStyle(.secondary)
                    }
                    if appState.authStatus == .limited {
                        Button("管理可访问的照片") {
                            presentLimitedPicker()
                        }
                    }
                    if !appState.authStatus.canAccessLibrary {
                        Button("重新请求 / 打开设置") {
                            Task { await appState.requestAccess() }
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "Linger（去留学习版）")
                    LabeledContent("版本", value: "1.0.0")
                    Text("学习项目：随机回顾 + 顺手整理。不含订阅与云同步。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var authText: String {
        switch appState.authStatus {
        case .authorized: return "已授权"
        case .limited: return "部分照片"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未决定"
        }
    }

    private func presentLimitedPicker() {
        // 当前 SDK 的 API 需要 UIViewController，从 key window 取根控制器
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            return
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
