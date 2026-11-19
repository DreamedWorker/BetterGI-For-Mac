//
//  KeySimulator.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation

/// 通过 Quartz 事件在 HID 层模拟键盘输入。
nonisolated enum KeySimulator {
    /// kVK_ANSI_F（Carbon HIToolbox/Events.h）
    static let keyF: CGKeyCode = 0x03

    /// 写入 `eventSourceUserData`，用于区分 BetterGI 合成的事件。
    static let eventMarker: Int64 = 0x4247_4921

    private static let releaseQueue = DispatchQueue(
        label: "BetterGI.input.keyboard",
        qos: .userInteractive
    )

    /// 当前进程是否允许发送事件。系统在进程内会缓存查询结果，授权后需重启 App 才会变化。
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// 按下并在 `holdDuration` 后松开一个键。
    ///
    /// 按住一小段时间而不是瞬间松开：游戏按帧读取按键状态，
    /// 过短的按键可能落在两帧之间被忽略。
    @discardableResult
    static func tap(_ keyCode: CGKeyCode, holdDuration: TimeInterval = 0.05) -> Bool {
        guard canPostEvents, let keyDown = makeEvent(keyCode, keyDown: true) else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        releaseQueue.asyncAfter(deadline: .now() + holdDuration) {
            makeEvent(keyCode, keyDown: false)?.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func makeEvent(_ keyCode: CGKeyCode, keyDown: Bool) -> CGEvent? {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
        event?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        return event
    }
}
