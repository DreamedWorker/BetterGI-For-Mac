//
//  TemplateMatcher.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation
import opencv2

/// 在采集画面的指定区域内做模板匹配（TM_CCOEFF_NORMED，灰度）。
///
/// 模板是 1080p 下的尺寸。游戏画面高于 1080p 时先把搜索区域缩到 1080p 等效尺寸再匹配，
/// 低于 1080p 时缩小模板，避免放大带来的模糊。
/// 缩放后的模板会被缓存，只能在同一个串行队列上使用。
nonisolated final class TemplateMatcher {
    nonisolated struct Match {
        /// 最佳匹配度
        let score: Double
        /// 匹配位置（采集画面像素坐标）
        let rect: CGRect
        /// 实际参与匹配的灰度图（可能已缩放），供进一步校验
        let workImage: Mat
        /// 匹配位置在 `workImage` 中的坐标
        let workRect: PixelRect
    }

    private var resizedTemplates: [String: Mat] = [:]

    /// - Parameters:
    ///   - region: 搜索区域（采集画面像素坐标）
    ///   - gameScale: 游戏画面相对 1080p 的缩放比例
    ///   - scaleFactors: 在 `gameScale` 附近额外尝试的倍率，用于容忍游戏区域推算误差
    func bestMatch(
        _ asset: TemplateAsset,
        in frame: BGRAFrame,
        region: CGRect,
        gameScale: Double,
        scaleFactors: [Double] = [1.0]
    ) -> Match? {
        guard gameScale > 0, let roi = PixelRect(region, within: frame.width, frame.height) else {
            return nil
        }

        let workScale = min(gameScale, 1.0)
        let resample = workScale / gameScale
        var gray = frame.grayMat(in: roi)
        if resample < 0.999 {
            let resized = Mat()
            Imgproc.resize(
                src: gray,
                dst: resized,
                dsize: Size2i(
                    width: Int32(max(1, (Double(roi.width) * resample).rounded())),
                    height: Int32(max(1, (Double(roi.height) * resample).rounded()))
                ),
                fx: 0,
                fy: 0,
                interpolation: InterpolationFlags.INTER_AREA.rawValue
            )
            gray = resized
        }

        var best: (score: Double, rect: PixelRect)?
        for factor in scaleFactors {
            let width = Int((Double(asset.width) * workScale * factor).rounded())
            let height = Int((Double(asset.height) * workScale * factor).rounded())
            guard width >= 6, height >= 6, width <= Int(gray.cols()), height <= Int(gray.rows()) else {
                continue
            }

            let result = Mat()
            Imgproc.matchTemplate(
                image: gray,
                templ: template(asset, width: width, height: height),
                result: result,
                method: .TM_CCOEFF_NORMED
            )
            let extremum = Core.minMaxLoc(result)
            guard extremum.maxVal.isFinite else { continue }

            if best.map({ extremum.maxVal > $0.score }) ?? true {
                let location = PixelRect(
                    x: Int(extremum.maxLoc.x),
                    y: Int(extremum.maxLoc.y),
                    width: width,
                    height: height
                )
                best = (extremum.maxVal, location)
            }
        }

        guard let best else { return nil }

        let rect = CGRect(
            x: Double(roi.x) + Double(best.rect.x) / resample,
            y: Double(roi.y) + Double(best.rect.y) / resample,
            width: Double(best.rect.width) / resample,
            height: Double(best.rect.height) / resample
        )
        return Match(score: best.score, rect: rect, workImage: gray, workRect: best.rect)
    }

    private func template(_ asset: TemplateAsset, width: Int, height: Int) -> Mat {
        if width == asset.width, height == asset.height {
            return asset.template
        }

        let key = "\(asset.name)@\(width)x\(height)"
        if let cached = resizedTemplates[key] {
            return cached
        }

        let resized = Mat()
        let isShrinking = width < asset.width || height < asset.height
        Imgproc.resize(
            src: asset.template,
            dst: resized,
            dsize: Size2i(width: Int32(width), height: Int32(height)),
            fx: 0,
            fy: 0,
            interpolation: (isShrinking ? InterpolationFlags.INTER_AREA : InterpolationFlags.INTER_LINEAR).rawValue
        )
        resizedTemplates[key] = resized
        return resized
    }
}
