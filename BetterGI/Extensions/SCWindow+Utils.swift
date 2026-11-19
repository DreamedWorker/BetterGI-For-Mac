//
//  SCWindow+Utils.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Foundation
import ScreenCaptureKit

extension SCWindow {
    /// 优先显示窗口标题；没有标题时退回应用名称。
    var displayTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        if !displayAppName.isEmpty {
            return displayAppName
        }
        return "未命名窗口"
    }

    /// 窗口所属应用名。个别系统窗口取不到应用名，此时返回空字符串。
    var displayAppName: String {
        owningApplication?.applicationName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// `SCWindow.frame` 的单位是点，不是像素。
    var displaySizeLabel: String {
        let width = Int(frame.width.rounded())
        let height = Int(frame.height.rounded())
        return "\(width) × \(height)"
    }

    /// 窗口标题与应用名相同时不再重复显示应用名。
    var displaySubtitle: String {
        guard !displayAppName.isEmpty, displayTitle != displayAppName else {
            return displaySizeLabel
        }
        return "\(displayAppName) · \(displaySizeLabel)"
    }

    /// 预览区域使用的宽高比，限制在合理范围内避免极端窗口把画面压得很奇怪。
    var previewAspectRatio: CGFloat {
        guard frame.height > 0 else { return 16.0 / 9.0 }

        let ratio = frame.width / frame.height
        return min(max(ratio, 1.25), 2.2)
    }
}
