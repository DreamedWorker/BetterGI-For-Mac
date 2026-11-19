//
//  GameWindowFocus.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import AppKit
import CoreGraphics
import Foundation

/// 自动化任务操作的目标窗口。
nonisolated struct GameWindowTarget: Equatable, Sendable {
    let windowID: CGWindowID
    let processID: pid_t
}

/// 判断游戏窗口当前能否接收键盘输入。
nonisolated enum GameWindowFocus {
    /// 能够作为游戏窗口识别的最新大小。
    private static let minimumWindowSize = CGSize(width: 200, height: 150)

    static func isFocused(_ target: GameWindowTarget, frontmostProcessID: pid_t?) -> Bool {
        guard frontmostProcessID == target.processID else {
            return false
        }

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        // 列表按从前到后的顺序排列。
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int) == Int(target.processID) else {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }

            if let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: boundsInfo),
               bounds.width < minimumWindowSize.width || bounds.height < minimumWindowSize.height {
                continue
            }

            return (info[kCGWindowNumber as String] as? Int) == Int(target.windowID)
        }

        return false
    }
}

/// 在主线程跟踪前台应用，供处理队列随时读取。
nonisolated final class FrontmostAppMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var processID: pid_t?
    private var observer: (any NSObjectProtocol)?

    var frontmostProcessID: pid_t? {
        lock.withLock { processID }
    }

    @MainActor
    func start() {
        guard observer == nil else { return }

        update(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(application?.processIdentifier)
        }
    }

    @MainActor
    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        update(nil)
    }

    private func update(_ processID: pid_t?) {
        lock.withLock { self.processID = processID }
    }
}
