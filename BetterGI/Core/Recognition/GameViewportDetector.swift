//
//  GameViewportDetector.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation

/// 在采集到的整个窗口画面里找出 16:9 的游戏画面区域（像素坐标，原点左上角）。
///
/// 采集的是整个窗口，游戏画面只是其中一部分：
/// - Wine：窗口 = macOS 标题栏 + 游戏客户区。
/// - Chrome（云游戏，窗口模式）：窗口 = 标签栏/工具栏 + 网页内容；
///   网页里的游戏画面保持 16:9，窗口比例不符时上下或左右留有纯色黑边。
///
/// 两种情况下，去掉底部和左右的纯色边之后，游戏画面都贴着底边并占满宽度，
/// 因此从底边按 16:9 向上推出游戏区域，就能同时排除标题栏、浏览器工具栏和黑边。
///
/// 画面整体变暗（加载、过场）时检测会失败或不准，所以检测结果要连续几次一致才会替换当前结果。
nonisolated final class GameViewportDetector {
    static let aspectRatio = 16.0 / 9.0

    /// 两次检测的最小间隔；游戏区域只会在窗口尺寸变化时改变，没必要每帧都算。
    private let detectionInterval: TimeInterval = 0.5
    /// 新结果需要连续出现的次数，用来过滤暗场景造成的误判。
    private let requiredConfirmations = 3

    private(set) var viewport: CGRect?
    private var pendingViewport: CGRect?
    private var pendingCount = 0
    private var lastDetectionTime: TimeInterval = -.infinity
    private var lastFrameWidth = 0
    private var lastFrameHeight = 0

    func update(with frame: BGRAFrame, now: TimeInterval) -> CGRect? {
        // 采集尺寸变化后旧结果不再有效，立即重新检测。
        if frame.width != lastFrameWidth || frame.height != lastFrameHeight {
            lastFrameWidth = frame.width
            lastFrameHeight = frame.height
            viewport = nil
            pendingViewport = nil
            pendingCount = 0
            lastDetectionTime = -.infinity
        }

        guard now - lastDetectionTime >= detectionInterval else {
            return viewport
        }
        lastDetectionTime = now

        guard let detected = Self.detect(in: frame) else {
            return viewport
        }

        guard let current = viewport else {
            viewport = detected
            return detected
        }

        if Self.isClose(detected, current) {
            pendingViewport = nil
            pendingCount = 0
            return current
        }

        if let pendingViewport, Self.isClose(pendingViewport, detected) {
            pendingCount += 1
        } else {
            pendingViewport = detected
            pendingCount = 1
        }

        if pendingCount >= requiredConfirmations {
            viewport = detected
            pendingViewport = nil
            pendingCount = 0
        }
        return viewport
    }

    // MARK: - 检测

    /// 在缩小后的亮度图上找内容边界，再换算回原始像素坐标。
    ///
    /// 黑边总是对称的（网页和 ScreenCaptureKit 都把画面居中），而游戏里的暗色区域不会恰好对称，
    /// 所以只有对称的纯色边才会被当作黑边裁掉。
    static func detect(in frame: BGRAFrame) -> CGRect? {
        guard let grid = LumaGrid(frame: frame) else { return nil }

        // 1. 去掉底部的纯色行。
        var bottom = grid.height - 1
        while bottom >= 0, grid.isFlatRow(bottom) {
            bottom -= 1
        }
        guard bottom >= grid.height / 4 else { return nil }

        // 2. 只在底部附近的一段行里判断左右纯色列，避免把顶部的标题栏、工具栏算进来。
        let bandEnd = max(1, bottom - grid.height * 3 / 100)
        let bandStart = max(0, min(bandEnd - 1, bottom - grid.height * 3 / 10))
        let band = bandStart..<bandEnd
        var left = 0
        while left < grid.width, grid.isFlatColumn(left, rows: band) {
            left += 1
        }
        var right = grid.width - 1
        while right > left, grid.isFlatColumn(right, rows: band) {
            right -= 1
        }
        if abs(left - (grid.width - 1 - right)) > max(2, grid.width / 100) {
            // 左右不对称：是游戏画面边缘的暗色区域，不是黑边。
            left = 0
            right = grid.width - 1
        }
        guard right - left + 1 >= grid.width / 4 else { return nil }

        // 3. 以底边和宽度按 16:9 推出游戏区域。
        guard var rect = fit(grid, bottom: bottom, left: left, right: right) else { return nil }

        // 4. 底部裁掉了纯色行时，游戏画面上方也应有同样高的黑边（网页内上下居中）；
        //    或者整个采集画面顶部有同样高的黑边（ScreenCaptureKit 缩放留边）。都没有就说明裁错了。
        let bottomBar = grid.height - 1 - bottom
        if bottomBar >= 2 {
            let gameTopRow = Int(rect.minY / grid.stepY)
            let barAboveGame = max(0, gameTopRow - bottomBar)..<max(0, gameTopRow)
            let isCentered = grid.flatRowRatio(barAboveGame) >= 0.6
                || grid.flatRowRatio(0..<bottomBar) >= 0.6
            if !isCentered {
                guard let untrimmed = fit(grid, bottom: grid.height - 1, left: left, right: right) else {
                    return nil
                }
                rect = untrimmed
            }
        }

        guard rect.width >= 320, rect.height >= 180 else { return nil }
        return rect
    }

    /// 以 `bottom` 行为底边、`left`～`right` 列为宽度，按 16:9 推出游戏区域（原始像素坐标）。
    private static func fit(_ grid: LumaGrid, bottom: Int, left: Int, right: Int) -> CGRect? {
        var minX = Double(left) * grid.stepX
        let maxX = min(grid.frameWidth, Double(right + 1) * grid.stepX)
        let maxY = min(grid.frameHeight, Double(bottom + 1) * grid.stepY)
        var width = maxX - minX
        var height = width / aspectRatio

        if height > maxY {
            // 内容比 16:9 更宽却没找到左右黑边：改为以高度为准、水平居中。
            height = maxY
            let fittedWidth = height * aspectRatio
            minX += (width - fittedWidth) / 2
            width = fittedWidth
        }

        guard width > 0, height > 0 else { return nil }
        return CGRect(x: minX, y: maxY - height, width: width, height: height)
    }

    /// 各边误差都在宽度的 2% 以内视为同一个结果。
    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance = max(a.width, b.width) * 0.02
        return abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance
            && abs(a.maxY - b.maxY) <= tolerance
    }
}

/// 按最近邻采样缩小后的亮度图（宽约 480），用于快速判断纯色边。
nonisolated private struct LumaGrid {
    let width: Int
    let height: Int
    let stepX: Double
    let stepY: Double
    let frameWidth: Double
    let frameHeight: Double
    private var values: [UInt8]

    /// 纯色边：亮度几乎没有起伏，并且足够暗（黑边、深色网页背景）。
    private static let flatRange = 8
    private static let flatMaxLuminance = 48

    init?(frame: BGRAFrame) {
        let width = min(frame.width, 480)
        guard width >= 64, frame.height >= 36 else { return nil }

        let stepX = Double(frame.width) / Double(width)
        let height = max(1, Int(Double(frame.height) / stepX))
        let stepY = Double(frame.height) / Double(height)

        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let y = min(frame.height - 1, Int((Double(row) + 0.5) * stepY))
            for column in 0..<width {
                let x = min(frame.width - 1, Int((Double(column) + 0.5) * stepX))
                values[row * width + column] = UInt8(frame.luminance(x: x, y: y))
            }
        }

        self.width = width
        self.height = height
        self.stepX = stepX
        self.stepY = stepY
        self.frameWidth = Double(frame.width)
        self.frameHeight = Double(frame.height)
        self.values = values
    }

    /// 两侧各留 5%，避开窗口圆角处的透明像素。
    func isFlatRow(_ row: Int) -> Bool {
        let margin = width / 20
        return isFlat((margin..<(width - margin)).lazy.map { values[row * width + $0] })
    }

    func isFlatColumn(_ column: Int, rows: Range<Int>) -> Bool {
        isFlat(rows.lazy.map { values[$0 * width + column] })
    }

    /// `rows` 中纯色行所占比例；范围为空时返回 0。
    func flatRowRatio(_ rows: Range<Int>) -> Double {
        let clamped = rows.clamped(to: 0..<height)
        guard !clamped.isEmpty else { return 0 }
        let flatCount = clamped.filter(isFlatRow).count
        return Double(flatCount) / Double(clamped.count)
    }

    private func isFlat<S: Sequence>(_ samples: S) -> Bool where S.Element == UInt8 {
        var minValue = UInt8.max
        var maxValue = UInt8.min
        for value in samples {
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }
        guard minValue <= maxValue else { return false }
        return Int(maxValue) <= Self.flatMaxLuminance && Int(maxValue - minValue) <= Self.flatRange
    }
}
