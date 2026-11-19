//
//  WelcomeView.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Combine
import SwiftUI

struct WelcomeView: View {

    /// 明确完成或跳过引导时调用。
    var onFinish: () -> Void = {}
    /// 由外层负责重新启动 App。
    var onRestart: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var permissions = PermissionCenter()

    private let brandBlue = Color(red: 0.22, green: 0.49, blue: 0.98)
    private let brandTeal = Color(red: 0.12, green: 0.74, blue: 0.76)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    featureSection
                    permissionSection
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: 680, height: 660)
        .tint(brandBlue)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await monitorPermissions() }
        .onChange(of: permissions.allGranted, initial: true) { _, allGranted in
            // 所有权限都已开启后，下次启动不再自动弹出引导。
            if allGranted {
                AppPreferences.isAppFirstOpen = false
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            // 从系统设置切回 App 时立即刷新状态。
            permissions.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            AppIconView(size: 96)

            VStack(alignment: .leading, spacing: 7) {
                Text("欢迎使用 BetterGI")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("为《原神》打造的 macOS 智能自动化助手")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    tag("本机运行", systemImage: "desktopcomputer")
                    tag("视觉驱动", systemImage: "eye")
                    tag("非侵入式", systemImage: "shield.lefthalf.filled")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [brandBlue.opacity(0.14), brandTeal.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(brandBlue.opacity(0.12), lineWidth: 1)
        }
    }

    // MARK: - Features

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading("主要功能", "把重复的游戏日常交给 BetterGI")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
//                FeatureCard(
//                    systemImage: "bolt.fill",
//                    tint: .orange,
//                    title: "一键一条龙",
//                    detail: "自动委托、秘境与领取奖励"
//                )
                FeatureCard(
                    systemImage: "hand.point.up.left.fill",
                    tint: .blue,
                    title: "智能交互",
                    detail: "自动拾取、自动对话与选项"
                )
//                FeatureCard(
//                    systemImage: "gamecontroller.fill",
//                    tint: .purple,
//                    title: "丰富玩法",
//                    detail: "自动钓鱼、自动伐木与烹饪"
//                )
                FeatureCard(
                    systemImage: "viewfinder",
                    tint: .green,
                    title: "本机视觉识别",
                    detail: "实时分析画面，不修改游戏文件"
                )
            }
        }
    }

    // MARK: - Permissions

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("授予必要权限")
                        .font(.system(size: 16, weight: .semibold))

                    Text("BetterGI 通过画面识别和模拟键鼠操作完成自动化，需要以下两项系统权限。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                PermissionProgress(
                    grantedCount: permissions.grantedCount,
                    totalCount: AppPermission.allCases.count
                )
            }

            ForEach(AppPermission.allCases) { permission in
                PermissionCard(
                    permission: permission,
                    isGranted: permissions.isGranted(permission),
                    needsManualSetup: permissions.didRequest(permission),
                    requestAction: { permissions.request(permission) },
                    openSettingsAction: {
                        permissions.openSystemSettings(for: permission)
                    }
                )
            }

            privacyNote
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(
                    permissions.shouldSuggestRelaunch
                        ? "两项权限仅用于本机的画面识别与自动化操作。在系统设置中开启权限后，需要重新启动 App，状态才会更新并生效。"
                        : "两项权限仅用于本机的画面识别与自动化操作。更改权限后，可能需要重新启动 App 才会生效。"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if permissions.shouldSuggestRelaunch {
                    Button {
                        restart()
                    } label: {
                        Label("重新启动 BetterGI", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brandBlue)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 14) {
                Button("稍后设置") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                Text(
                    permissions.allGranted
                        ? "权限已就绪"
                        : "稍后也可以在「使用引导」中重新设置"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Button {
                    finish()
                } label: {
                    Text("开始使用")
                        .frame(minWidth: 86)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!permissions.allGranted)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 15)
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func tag(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private func sectionHeading(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }

    private func restart() {
        onRestart()
    }

    /// 停留在欢迎页期间轮询权限状态。
    /// 从系统设置切回 App 时，`didBecomeActiveNotification` 也会触发刷新。
    private func monitorPermissions() async {
        permissions.refresh()

        while !Task.isCancelled && !permissions.allGranted {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            permissions.refresh()
        }
    }
}

// MARK: - FeatureCard

private struct FeatureCard: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - PermissionCard

private struct PermissionCard: View {
    let permission: AppPermission
    let isGranted: Bool
    let needsManualSetup: Bool
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isGranted ? Color.green : Color.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    (isGranted ? Color.green : Color.accentColor).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(permission.title)
                        .font(.system(size: 14, weight: .semibold))

                    PermissionStatusBadge(isGranted: isGranted)
                }

                Text(permission.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            actionView
                .frame(width: 112, alignment: .trailing)
        }
        .padding(13)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isGranted ? Color.green.opacity(0.18) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private var actionView: some View {
        if isGranted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .accessibilityLabel("已授权")
        } else if needsManualSetup {
            Button("打开系统设置") {
                openSettingsAction()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("在系统设置中允许 BetterGI 使用\(permission.title)")
        } else {
            Button("去授权") {
                requestAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("向系统申请\(permission.title)权限")
        }
    }
}

// MARK: - Small components

private struct PermissionStatusBadge: View {
    let isGranted: Bool

    var body: some View {
        Text(isGranted ? "已开启" : "未开启")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isGranted ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                (isGranted ? Color.green : Color.orange).opacity(0.12),
                in: Capsule()
            )
    }
}

private struct PermissionProgress: View {
    let grantedCount: Int
    let totalCount: Int

    private var isComplete: Bool {
        grantedCount == totalCount
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                .font(.system(size: 10, weight: .semibold))

            Text(isComplete ? "已完成" : "\(grantedCount)/\(totalCount)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isComplete ? Color.green : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            (isComplete ? Color.green : Color.primary).opacity(0.08),
            in: Capsule()
        )
        .accessibilityLabel("权限完成度 \(grantedCount) / \(totalCount)")
    }
}
