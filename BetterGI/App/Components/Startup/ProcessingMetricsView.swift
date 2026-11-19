//
//  ProcessingMetricsView.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

struct ProcessingMetricsView: View {
    let session: StartupViewModel

    var body: some View {
        HStack(spacing: 0) {
            MetricCell(title: "采集帧率", value: formattedFPS(session.captureFPS), unit: "fps")
            MetricDivider()
            MetricCell(title: "处理帧率", value: formattedFPS(session.processingFPS), unit: "fps")
            MetricDivider()
            MetricCell(title: "处理耗时", value: formattedDuration(session.processingDuration), unit: "ms")
            MetricDivider()
            MetricCell(title: "累计丢帧", value: "\(session.droppedFrames)")
        }
    }

    private func formattedFPS(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(format: "%.1f", value)
    }

    private func formattedDuration(_ value: TimeInterval) -> String {
        guard value > 0 else { return "—" }
        return String(format: "%.1f", value * 1000)
    }
}

struct MetricCell: View {
    let title: String
    let value: String
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !unit.isEmpty, value != "—" {
                    Text(unit)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 10)
    }
}
