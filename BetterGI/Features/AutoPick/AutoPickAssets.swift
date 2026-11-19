//
//  AutoPickAssets.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Foundation

/// 自动拾取用到的识别资源。
nonisolated final class AutoPickAssets: @unchecked Sendable {
    static let feature = "AutoPick"

    /// 拾取键图标（F）
    let pickKey: TemplateAsset
    /// 千星奇遇中出现的 L 键提示：出现时不拾取
    let miliastraKey: TemplateAsset
    /// 交互选项的设置图标（解谜、电梯、活动等）：出现时不拾取
    let settingsIcon: TemplateAsset

    init(bundle: Bundle) throws {
        let assets = try RecognitionAssets.load(feature: Self.feature, bundle: bundle)

        func require(_ name: String, needsRegion: Bool) throws -> TemplateAsset {
            guard let asset = assets[name] else {
                throw RecognitionAssetError.missingObject(name, feature: Self.feature)
            }
            if needsRegion, asset.region == nil {
                throw RecognitionAssetError.missingRegion(name, feature: Self.feature)
            }
            return asset
        }

        pickKey = try require("F", needsRegion: true)
        miliastraKey = try require("L", needsRegion: true)
        settingsIcon = try require("SettingsIcon", needsRegion: false)
    }
}
