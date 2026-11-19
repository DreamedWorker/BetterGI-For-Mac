//
//  PickKeyGlyph.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation
import opencv2

/// 拾取键图标（白色底上一个深色的「F」）的结构校验。
///
/// 模板匹配使用 `Resources/AutoPick/1920x1080/F.png`。这里的区域坐标按该模板的 32×32 网格描述，
/// 匹配到的位置无论缩放成多大，都按比例换算。
nonisolated enum PickKeyGlyph {
    /// 网格边长，等于 F.png 在 1080p 下的边长
    static let gridSize = 32.0

    /// 结构校验中应为深色的区域：上横右段、中横、竖笔画中段。
    private static let inkZones: [CGRect] = [
        CGRect(x: 15, y: 6, width: 6, height: 2),
        CGRect(x: 15, y: 14, width: 5, height: 2),
        CGRect(x: 11, y: 9, width: 3, height: 12),
    ]

    /// 结构校验中应为浅色的区域：字形左侧留白、两横之间、中横下方。
    /// 最后一块正好覆盖「E」底横所在的位置，用来区分 E。
    private static let paperZones: [CGRect] = [
        CGRect(x: 2, y: 6, width: 6, height: 18),
        CGRect(x: 16.5, y: 9.5, width: 5, height: 3),
        CGRect(x: 15.5, y: 21.5, width: 5.5, height: 3),
    ]

    /// 图标整体明暗差（最亮的浅色区域与最暗的笔画之差）的下限
    private static let minimumGlyphContrast = 60.0
    /// 「最暗的浅色区域」与「最亮的笔画区域」之差，至少要达到整体明暗差的这个比例。
    /// 用相对值而不是固定值：窗口较小或云游戏画面模糊时，细笔画会变浅，但结构依然成立。
    private static let minimumSeparationRatio = 0.35

    /// 检查 `gray` 中以 (x, y) 为左上角、边长 `size` 的区域是否具有「F」的结构。
    ///
    /// 模板匹配主要由竖笔画贡献得分，一根竖线或「E」也能得到不低的分数；
    /// 这里再比较几处关键区域的明暗，排除这类相似图形。
    static func hasGlyphStructure(in gray: Mat, x: Int, y: Int, size: Int) -> Bool {
        let rows = Int(gray.rows())
        let cols = Int(gray.cols())
        guard size > 0, x >= 0, y >= 0, x + size <= cols, y + size <= rows else {
            return false
        }

        let scale = Double(size) / gridSize
        let pointer = gray.dataPointer()
        let stride = gray.step1()

        func meanLuminance(_ zone: CGRect) -> Double {
            let minX = x + Int((zone.minX * scale).rounded())
            let minY = y + Int((zone.minY * scale).rounded())
            let maxX = max(minX + 1, x + Int((zone.maxX * scale).rounded()))
            let maxY = max(minY + 1, y + Int((zone.maxY * scale).rounded()))

            var sum = 0
            var count = 0
            for row in minY..<min(maxY, y + size) {
                let line = pointer + row * stride
                for column in minX..<min(maxX, x + size) {
                    sum += Int(line[column])
                    count += 1
                }
            }
            return count > 0 ? Double(sum) / Double(count) : 0
        }

        let paper = paperZones.map(meanLuminance)
        let ink = inkZones.map(meanLuminance)
        guard let darkestPaper = paper.min(), let lightestPaper = paper.max(),
              let darkestInk = ink.min(), let lightestInk = ink.max() else {
            return false
        }

        let glyphContrast = lightestPaper - darkestInk
        guard glyphContrast >= minimumGlyphContrast else { return false }
        return darkestPaper - lightestInk >= glyphContrast * minimumSeparationRatio
    }
}
