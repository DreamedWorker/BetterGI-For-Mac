//
//  ItemNameRecognizer.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// 使用系统自带的 Vision 文字识别读取拾取提示中的物品名称。
nonisolated final class ItemNameRecognizer {
    /// 识别 `pixelBuffer` 中 `rect`（像素坐标，原点左上角）内的文字，没有识别到时返回 `nil`。
    func recognize(in pixelBuffer: CVPixelBuffer, rect: CGRect) -> String? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        // 中文只有 accurate 模式支持
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // 物品名多为专有名词，语言纠正反而容易改错
        request.usesLanguageCorrection = false
        // regionOfInterest 使用归一化坐标，原点在左下角
        request.regionOfInterest = CGRect(
            x: clipped.minX / width,
            y: (height - clipped.maxY) / height,
            width: clipped.width / width,
            height: clipped.height / height
        )

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let text = (request.results ?? [])
            .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined()
            .filter { !$0.isWhitespace }
        return text.isEmpty ? nil : text
    }
}
