import SwiftUI
import UIKit

/// 相册权限引导页
struct PermissionView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.18),
                    Color(red: 0.08, green: 0.18, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("Linger")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundStyle(.white)

                Text("随机回顾相册里的瞬间\n顺手留下值得保留的，删掉其余的")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 12) {
                    bullet("像刷短视频一样看照片")
                    bullet("上划标记删除，组末再确认")
                    bullet("不展示待办压力，只记录已完成")
                }
                .padding(.horizontal, 40)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                Spacer()

                Button {
                    Task { await request() }
                } label: {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(buttonTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isRequesting)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }

    private var buttonTitle: String {
        switch appState.authStatus {
        case .denied, .restricted:
            return "打开系统设置"
        default:
            return "允许访问相册"
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func request() async {
        errorMessage = nil
        // 已拒绝则引导去设置，无法再弹系统框
        if appState.authStatus == .denied || appState.authStatus == .restricted {
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                errorMessage = "无法打开系统设置"
                return
            }
            await UIApplication.shared.open(url)
            return
        }

        isRequesting = true
        defer { isRequesting = false }
        await appState.requestAccess()
        if !appState.authStatus.canAccessLibrary {
            errorMessage = "需要相册读写权限才能回顾并删除照片"
        }
    }
}
