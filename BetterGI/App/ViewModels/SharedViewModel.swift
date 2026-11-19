//
//  SharedViewModel.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Foundation
import ScreenCaptureKit

@Observable
final class SharedViewModel {
    var avaliableWindows: [SCWindow] = []

    /// 当前选中的操作目标窗口
    var selectedWindowID: CGWindowID?

    var selectedWindow: SCWindow? {
        guard let selectedWindowID else { return nil }
        return avaliableWindows.first { $0.windowID == selectedWindowID }
    }

    func getOrRefreshAvailableContents() async {
        guard let availableContent = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
        avaliableWindows.removeAll()
        avaliableWindows = filterWindows(availableContent.windows)
    }
    
    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
}
