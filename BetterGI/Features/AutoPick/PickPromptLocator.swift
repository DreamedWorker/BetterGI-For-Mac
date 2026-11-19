//
//  PickPromptLocator.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation

/// 在游戏画面中寻找拾取提示，并检查需要跳过的情况。
nonisolated final class PickPromptLocator {
    nonisolated struct Match: Sendable {
        /// 拾取键模板的最佳匹配度
        let score: Double
        /// 是否通过字形结构校验
        let hasGlyphStructure: Bool
        /// 拾取键图标在采集画面中的位置（像素）
        let keyRect: CGRect
        /// 游戏画面相对 1080p 的缩放比例
        let gameScale: Double
    }

    /// 拾取选项一行的布局：相对拾取键图标左边缘的偏移（1080p 像素）。
    nonisolated enum RowLayout {
        static let iconLeft = 60.0
        static let nameLeft = 115.0
        static let nameRight = 400.0
        /// 图标、名称区域上下各放宽的距离
        static let verticalPadding = 4.0
    }

    /// L 键、设置图标的匹配阈值，取上游识别对象的默认值。
    static let auxiliaryThreshold = 0.8

    /// 上游直接采集游戏客户区，本项目则从整个窗口推算游戏区域，
    /// 所以在配置的搜索区域外再放宽一圈（1080p 像素），容忍推算误差。
    private static let pickKeyRegionMargin = 20.0
    private static let miliastraRegionMargin = 10.0

    /// 在推算的比例附近多试几个尺寸，容忍游戏区域高度的推算误差。
    private static let scaleFactors: [Double] = [1.0, 0.94, 1.06]

    private let assets: AutoPickAssets
    private let matcher = TemplateMatcher()

    init(assets: AutoPickAssets) {
        self.assets = assets
    }

    func locate(in frame: BGRAFrame, viewport: CGRect) -> Match? {
        let gameScale = viewport.height / 1080
        guard gameScale >= 0.3, let region = assets.pickKey.region else { return nil }

        let margin = Self.pickKeyRegionMargin * gameScale
        let searchArea = Self.absolute(region, in: viewport, scale: gameScale)
            .insetBy(dx: -margin, dy: -margin)

        guard let match = matcher.bestMatch(
            assets.pickKey,
            in: frame,
            region: searchArea,
            gameScale: gameScale,
            scaleFactors: Self.scaleFactors
        ) else {
            return nil
        }

        let hasStructure = PickKeyGlyph.hasGlyphStructure(
            in: match.workImage,
            x: match.workRect.x,
            y: match.workRect.y,
            size: match.workRect.width
        )
        return Match(
            score: match.score,
            hasGlyphStructure: hasStructure,
            keyRect: match.rect,
            gameScale: gameScale
        )
    }

    /// 千星奇遇：画面右侧出现 L 键提示时无需拾取。
    func showsMiliastraKey(in frame: BGRAFrame, viewport: CGRect) -> Bool {
        let gameScale = viewport.height / 1080
        guard let region = assets.miliastraKey.region else { return false }

        let margin = Self.miliastraRegionMargin * gameScale
        let searchArea = Self.absolute(region, in: viewport, scale: gameScale)
            .insetBy(dx: -margin, dy: -margin)
        let score = matcher.bestMatch(
            assets.miliastraKey,
            in: frame,
            region: searchArea,
            gameScale: gameScale,
            scaleFactors: Self.scaleFactors
        )?.score ?? 0
        return score >= Self.auxiliaryThreshold
    }

    /// 物品图标位置是设置图标：这是解谜、电梯、活动等交互选项，不是可拾取的物品。
    func showsSettingsIcon(in frame: BGRAFrame, nextTo match: Match) -> Bool {
        let scale = match.gameScale
        let padding = RowLayout.verticalPadding * scale
        let iconArea = CGRect(
            x: match.keyRect.minX + RowLayout.iconLeft * scale,
            y: match.keyRect.minY - padding,
            width: (RowLayout.nameLeft - RowLayout.iconLeft) * scale,
            height: match.keyRect.height + padding * 2
        )
        let score = matcher.bestMatch(
            assets.settingsIcon,
            in: frame,
            region: iconArea,
            gameScale: scale,
            scaleFactors: Self.scaleFactors
        )?.score ?? 0
        return score >= Self.auxiliaryThreshold
    }

    /// 把相对游戏画面的区域换算成采集画面坐标。
    private static func absolute(_ region: RegionExpression, in viewport: CGRect, scale: Double) -> CGRect {
        region
            .evaluate(scale: scale, width: viewport.width, height: viewport.height)
            .offsetBy(dx: viewport.minX, dy: viewport.minY)
    }
}
