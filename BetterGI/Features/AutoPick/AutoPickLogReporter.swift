//
//  AutoPickLogReporter.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation
import QuartzCore

nonisolated struct AutoPickLogEvent: Sendable {
    let message: String
    let level: LogEntry.Level
}

/// 把处理队列发布的 `AutoPickSnapshot` 转换成主线程日志。
@MainActor
final class AutoPickLogReporter {
    private var lastOutcome: AutoPickOutcome?
    private var lastPickCount = 0
    private var noticeLogTimes: [String: TimeInterval] = [:]
    private var hasReportedAssetsUnavailable = false

    /// - Parameter baselinePickCount: 当前报告里已有的拾取次数。中途开启时用它作为基准，
    ///   避免把开启前的历史拾取重复写进日志。
    func reset(baselinePickCount: Int = 0) {
        lastOutcome = nil
        lastPickCount = baselinePickCount
        noticeLogTimes.removeAll()
        hasReportedAssetsUnavailable = false
    }

    func drain(
        _ snapshot: AutoPickSnapshot,
        isEnabled: Bool
    ) -> [AutoPickLogEvent] {
        guard isEnabled else { return [] }

        var events: [AutoPickLogEvent] = []

        if snapshot.pickCount > lastPickCount {
            lastPickCount = snapshot.pickCount
            if let name = snapshot.lastPickedItem {
                events.append(AutoPickLogEvent(
                    message: "自动拾取：\(name)",
                    level: .success
                ))
            } else {
                events.append(AutoPickLogEvent(
                    message: "自动拾取：已按下 F（未识别到物品名称）",
                    level: .success
                ))
            }
        }

        guard snapshot.outcome != lastOutcome else { return events }
        lastOutcome = snapshot.outcome

        switch snapshot.outcome {
        case .assetsUnavailable(let message):
            guard !hasReportedAssetsUnavailable else { break }
            hasReportedAssetsUnavailable = true
            events.append(AutoPickLogEvent(
                message: "自动拾取识别资源加载失败：\(message ?? "未知错误")",
                level: .error
            ))

        case .waitingForFocus:
            appendNotice(
                key: "waitingForFocus",
                message: "自动拾取：识别到拾取提示，但游戏窗口不在前台，暂不按键",
                level: .warning,
                to: &events
            )

        case .skipped(.notAllowed(let itemName)):
            if let itemName {
                appendNotice(
                    key: "notAllowed:\(itemName)",
                    message: "自动拾取：跳过「\(itemName)」，不在白名单中",
                    level: .info,
                    to: &events
                )
            } else {
                appendNotice(
                    key: "notAllowed:nil",
                    message: "自动拾取：物品名称未识别，白名单无法匹配",
                    level: .info,
                    to: &events
                )
            }

        case .skipped(.nameUnavailable):
            appendNotice(
                key: "nameUnavailable",
                message: "自动拾取：物品名称未识别，白名单无法匹配",
                level: .warning,
                to: &events
            )

        case .skipped(.whitelistEmpty):
            appendNotice(
                key: "whitelistEmpty",
                message: "自动拾取：白名单为空，不会拾取任何物品。请填写白名单，或关闭「识别物品名称」以拾取全部。",
                level: .warning,
                to: &events
            )

        case .skipped(.settingsIcon):
            appendNotice(
                key: "settingsIcon",
                message: "自动拾取：跳过交互选项（物品图标为设置图标）",
                level: .info,
                to: &events
            )

        case .skipped(.miliastra):
            appendNotice(
                key: "miliastra",
                message: "自动拾取：检测到千星奇遇的 L 键提示，暂不拾取",
                level: .info,
                to: &events
            )

        case .disabled, .noViewport, .searching, .coolingDown, .picked, .inputUnavailable:
            break
        }

        return events
    }

    private func appendNotice(
        key: String,
        message: String,
        level: LogEntry.Level,
        to events: inout [AutoPickLogEvent]
    ) {
        let now = CACurrentMediaTime()
        guard now - (noticeLogTimes[key] ?? -.infinity) >= 5 else { return }
        noticeLogTimes[key] = now
        events.append(AutoPickLogEvent(message: message, level: level))
    }
}
