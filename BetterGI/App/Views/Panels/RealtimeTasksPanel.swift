//
//  RealtimeTasksPanel.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import SwiftUI

struct RealtimeTasksPanel: View {
    let session: StartupViewModel

    var onOpenStartup: () -> Void = {}

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("实时任务")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("开始录制后，已开启的任务会持续识别游戏画面并自动执行。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                recordingBadge
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 14) {
                    if !session.isRecording {
                        captureHint
                    }
                    AutoPickCard(session: session)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)
        }
        .background { PanelGradientBackground() }
    }

    @ViewBuilder
    private var recordingBadge: some View {
        if session.isRecording {
            let title = session.recordingWindowTitle.map { "录制中 · \($0)" } ?? "录制中"
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.10), in: Capsule())
            .frame(maxWidth: 240, alignment: .trailing)
        } else {
            Label("未录制", systemImage: "pause.circle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
    }

    private var captureHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(
                    Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1.5) {
                Text("尚未开始录制")
                    .font(.system(size: 12.5, weight: .medium))
                Text("实时任务需要先在「启动」页选择游戏窗口并开始录制。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onOpenStartup) {
                Label("前往启动", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppPalette.blue.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("切换到「启动」页")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PanelCardBackground() }
    }
}
