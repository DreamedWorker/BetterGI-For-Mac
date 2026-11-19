//
//  AppPermission.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import AppKit
import Combine
import CoreGraphics

/// BetterGI 运行自动化任务所需要的系统权限。
enum AppPermission: String, CaseIterable, Identifiable {
    /// 读取游戏窗口画面。
    case screenRecording
    /// 向游戏发送鼠标与键盘事件。
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenRecording:
            return "屏幕录制"
        case .accessibility:
            return "辅助功能"
        }
    }

    var detail: String {
        switch self {
        case .screenRecording:
            return "读取游戏窗口画面，用于识别任务、对话与界面状态。"
        case .accessibility:
            return "发送鼠标点击和键盘事件，代替你完成游戏内的重复操作。"
        }
    }

    var systemImage: String {
        switch self {
        case .screenRecording:
            return "rectangle.dashed.badge.record"
        case .accessibility:
            return "hand.tap.fill"
        }
    }

    /// 系统设置中对应隐私面板的深链接。
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .screenRecording:
            anchor = "Privacy_ScreenCapture"
        case .accessibility:
            anchor = "Privacy_Accessibility"
        }

        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        )
    }

    /// 向系统查询当前进程是否已获得该权限。
    /// 进程内只有第一次调用会真正查询，之后返回缓存结果，详见 `PermissionCenter.shouldSuggestRelaunch`。
    var isGrantedBySystem: Bool {
        switch self {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .accessibility:
            return CGPreflightPostEventAccess()
        }
    }

    /// 所需权限是否已全部开启。
    static var allGrantedBySystem: Bool {
        allCases.allSatisfy(\.isGrantedBySystem)
    }
}

/// 跟踪授权状态，并负责发起系统授权请求。
@MainActor
final class PermissionCenter: ObservableObject {

    @Published private(set) var screenRecordingGranted: Bool
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var didRequestScreenRecording = false
    @Published private(set) var didRequestAccessibility = false

    /// 本次启动后是否有权限从未开启变为已开启。
    /// 用于提示用户重新启动 App，使新权限立即生效。
    @Published private(set) var didGrantPermissionThisSession = false

    init() {
        screenRecordingGranted = AppPermission.screenRecording.isGrantedBySystem
        accessibilityGranted = AppPermission.accessibility.isGrantedBySystem
    }

    var grantedCount: Int {
        AppPermission.allCases.filter(isGranted).count
    }

    var allGranted: Bool {
        grantedCount == AppPermission.allCases.count
    }

    /// 是否应提示用户重新启动 App。
    ///
    /// `CGPreflightPostEventAccess()` 与 `CGPreflightScreenCaptureAccess()` 在进程内
    /// 只会向系统查询一次，之后一直返回缓存的结果。用户在系统设置中开启权限后，
    /// 当前进程无法感知变化，只有重新启动才能读到新状态。
    /// 因此只要发起过授权、但仍显示未开启，就提示重新启动。
    var shouldSuggestRelaunch: Bool {
        didGrantPermissionThisSession
            || (!allGranted && AppPermission.allCases.contains(where: didRequest))
    }

    func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .screenRecording:
            return screenRecordingGranted
        case .accessibility:
            return accessibilityGranted
        }
    }

    /// 是否已经发起过系统授权请求。
    /// 发起过后再次点击应打开系统设置，而不是重复请求。
    func didRequest(_ permission: AppPermission) -> Bool {
        switch permission {
        case .screenRecording:
            return didRequestScreenRecording
        case .accessibility:
            return didRequestAccessibility
        }
    }

    func refresh() {
        let isScreenRecordingGranted = AppPermission.screenRecording.isGrantedBySystem
        let isAccessibilityGranted = AppPermission.accessibility.isGrantedBySystem

        if (isScreenRecordingGranted && !screenRecordingGranted)
            || (isAccessibilityGranted && !accessibilityGranted) {
            didGrantPermissionThisSession = true
        }

        if isScreenRecordingGranted != screenRecordingGranted {
            screenRecordingGranted = isScreenRecordingGranted
        }

        if isAccessibilityGranted != accessibilityGranted {
            accessibilityGranted = isAccessibilityGranted
        }
    }

    /// 发起系统授权请求。屏幕录制与辅助功能都会弹出系统自己的授权提示。
    func request(_ permission: AppPermission) {
        switch permission {
        case .screenRecording:
            didRequestScreenRecording = true
            _ = CGRequestScreenCaptureAccess()

        case .accessibility:
            didRequestAccessibility = true
            _ = CGRequestPostEventAccess()
        }

        refresh()
    }

    func openSystemSettings(for permission: AppPermission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
