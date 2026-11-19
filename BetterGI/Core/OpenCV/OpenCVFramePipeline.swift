//
//  OpenCVFramePipeline.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation
import QuartzCore

/// 把采集到的帧交给处理队列，处理不过来时直接丢帧。
///
/// 处理结果真正交给主线程后才释放信号量，避免主线程消费不过来时结果无限堆积。
nonisolated final class OpenCVFramePipeline: @unchecked Sendable {
    private let processor: GameFrameProcessor
    private let queue = DispatchQueue(
        label: "BetterGI.opencv.processing",
        qos: .userInitiated
    )
    private let semaphore = DispatchSemaphore(value: 1)
    private let onResult: @MainActor @Sendable (FrameProcessingResult) -> Void

    init(
        processor: GameFrameProcessor = GameFrameProcessor(),
        onResult: @MainActor @Sendable @escaping (FrameProcessingResult) -> Void
    ) {
        self.processor = processor
        self.onResult = onResult
    }

    /// 提交一帧处理；忙碌时直接丢弃并返回 `false`。
    @discardableResult
    func submit(_ frame: CapturedFrame) -> Bool {
        guard semaphore.wait(timeout: .now()) == .success else {
            return false
        }

        queue.async { [self] in
            let start = CACurrentMediaTime()
            // OpenCV 的 Objective-C 接口会产生 autoreleased 对象，处理队列没有 runloop，
            // 需要每帧手动清一次，否则长时间运行内存会持续上涨。
            let result: FrameProcessingResult = autoreleasepool {
                do {
                    return .success(
                        try processor.process(frame),
                        duration: CACurrentMediaTime() - start
                    )
                } catch {
                    return .failure(error.localizedDescription)
                }
            }

            Task { @MainActor in
                defer { semaphore.signal() }
                onResult(result)
            }
        }

        return true
    }
}

nonisolated enum FrameProcessingResult: Sendable {
    case success(FrameAnalysis, duration: TimeInterval)
    case failure(String)
}
