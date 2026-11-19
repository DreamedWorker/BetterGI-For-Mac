//
//  AutoPickCard.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import SwiftUI

/// 自动拾取设置面板。
struct AutoPickCard: View {
    @Bindable var session: StartupViewModel

    /// 关键词输入框的原始文本。单独保存，避免每次输入都被格式化后改写光标位置。
    @State private var keywordText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("自动拾取")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer(minLength: 8)
                    Toggle("自动拾取", isOn: $session.autoPickSettings.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help("识别到拾取提示（F）时自动按下 F")
                }
                Text("识别到拾取提示（F）时自动按下 F；开启名称识别后，白名单只允许拾取名称包含指定关键词的物品。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
                .opacity(0.6)
            settingsRow
            whitelistField
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PanelCardBackground() }
        .onAppear {
            keywordText = session.autoPickSettings.allowedKeywords.joined(separator: " ")
        }
        .onChange(of: keywordText) { _, newValue in
            session.autoPickSettings.allowedKeywords = AutoPickSettings.parseKeywords(newValue)
        }
    }

    // MARK: - 设置

    private var settingsRow: some View {
        HStack(spacing: 10) {
            Toggle("识别物品名称", isOn: $session.autoPickSettings.recognizesItemName)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("使用系统文字识别读取物品名称；白名单依赖名称识别")
            Spacer(minLength: 8)
            Text("匹配阈值")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(
                value: $session.autoPickSettings.matchThreshold,
                in: AutoPickSettings.thresholdRange,
                step: 0.01
            )
            .controlSize(.mini)
            .frame(width: 110)
            .help("匹配度达到该值才视为拾取提示。误按时调高，漏按时调低。")
            Text(String(format: "%.2f", session.autoPickSettings.matchThreshold))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var whitelistField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                "白名单关键词，例如：甜甜花 矿石 天云草实",
                text: $keywordText
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .disabled(!session.autoPickSettings.recognizesItemName)
            .help("只有物品名称包含其中任意一个关键词时才拾取；需要开启「识别物品名称」。")
            Text(whitelistHint)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whitelistHint: String {
        guard session.autoPickSettings.recognizesItemName else {
            return "关闭名称识别后白名单不生效，将拾取所有物品。"
        }
        if session.autoPickSettings.allowedKeywords.isEmpty {
            return "白名单为空：不会拾取任何物品。填写关键词，或关闭名称识别以拾取全部。"
        }
        return "只拾取名称包含「\(session.autoPickSettings.allowedKeywords.joined(separator: "、"))」的物品。"
    }
}
