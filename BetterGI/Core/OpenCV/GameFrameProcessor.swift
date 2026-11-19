//
//  GameFrameProcessor.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import CoreGraphics
import Foundation
import QuartzCore

/// 一帧画面的通用处理结果。
nonisolated struct FrameAnalysis: Sendable {
    /// 采集画面尺寸（像素）
    let frameSize: CGSize
    /// 游戏画面在采集画面中的位置（像素），尚未定位时为 `nil`
    let viewport: CGRect?
}

nonisolated protocol GameFrameConsumer: AnyObject {
    /// 在处理队列上调用。`viewport` 为 `nil` 表示还没有定位到游戏画面。
    func process(
        frame: CapturedFrame,
        viewport: CGRect?,
        now: TimeInterval
    ) throws
}

nonisolated final class GameFrameProcessor {
    private let viewportDetector = GameViewportDetector()
    private let consumers: [any GameFrameConsumer]

    init(consumers: [any GameFrameConsumer] = []) {
        self.consumers = consumers
    }

    func process(_ frame: CapturedFrame) throws -> FrameAnalysis {
        let now = CACurrentMediaTime()

        // 锁定缓冲区期间只做纯像素计算，尽快解锁。
        let viewport = try BGRAFrame.withLocked(frame.pixelBuffer) { buffer in
            viewportDetector.update(with: buffer, now: now)
        }

        for consumer in consumers {
            try consumer.process(frame: frame, viewport: viewport, now: now)
        }

        return FrameAnalysis(
            frameSize: CGSize(width: frame.width, height: frame.height),
            viewport: viewport
        )
    }
}
