//
//  StartupLogView.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

struct StartupLogView: View {
    let logs: [LogEntry]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("运行日志")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                Button("清空") {
                    onClear()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .disabled(logs.isEmpty)
                .help("清空运行日志")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 9)

            Divider()
                .opacity(0.6)

            if logs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 18, weight: .light))
                    Text("暂无日志")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("开始或停止录制后，操作结果会记录在这里")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(logs) { entry in
                                LogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: logs.last?.id) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { PanelCardBackground() }
    }
}

// MARK: - 日志行

private struct LogRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 54, alignment: .leading)

            Image(systemName: entry.level.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(entry.level.color)
                .frame(width: 12)
                .padding(.top, 2)

            Text(entry.message)
                .font(.system(size: 10.5))
                .foregroundStyle(entry.level.textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 日志样式

private extension LogEntry.Level {
    var systemImage: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var textColor: Color {
        switch self {
        case .info:
            return .secondary
        case .success, .warning, .error:
            return .primary
        }
    }
}
