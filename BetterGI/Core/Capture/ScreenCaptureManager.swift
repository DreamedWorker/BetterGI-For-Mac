//
//  ScreenCaptureManager.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation
import ScreenCaptureKit

class ScreenCaptureManager: NSObject {
    private let window: SCWindow
    private let configuration: Configuration
    private let outputQueue = DispatchQueue(
        label: "BetterGI.ScreenRecorder.output",
        qos: .userInteractive
    )
    private let lock = NSLock()
    private var stream: SCStream?
    private var frameHandler: (@Sendable (CapturedFrame) -> Void)?
    private var errorHandler: (@Sendable (Error) -> Void)?
    
    /// 图像帧回调
    var onFrame: (@Sendable (CapturedFrame) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return frameHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            frameHandler = newValue
        }
    }
    
    /// 异常回调
    var onError: (@Sendable (Error) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return errorHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            errorHandler = newValue
        }
    }
    
    init(window: SCWindow, configuration: Configuration = .init()) {
        self.window = window
        self.configuration = configuration
        super.init()
    }
    
    // MARK: - 采集
    
    /// 开始屏幕采集
    func startCapture() async throws {
        guard !hasStream() else {
            return
        }
        
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let streamConfiguration = SCStreamConfiguration()
        // 输出分辨率
        streamConfiguration.width = max(
            1,
            Int(window.frame.width * CGFloat(configuration.scaleFactor))
        )
        
        streamConfiguration.height = max(
            1,
            Int(window.frame.height * CGFloat(configuration.scaleFactor))
        )
        // 图像格式：BGRA
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        // 帧率
        streamConfiguration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(
                max(1, configuration.framesPerSecond)
            )
        )
        // 缓冲区
        streamConfiguration.queueDepth = max(
            1,
            configuration.queueDepth
        )
        streamConfiguration.showsCursor = configuration.showsCursor
        // 忽略音频
        streamConfiguration.capturesAudio = false
        
        let newStream = SCStream(
            filter: filter,
            configuration: streamConfiguration,
            delegate: self
        )
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        guard installStream(newStream) else {
            return
        }
        
        do {
            try await newStream.startCapture()
        } catch {
            clearStream(ifIdenticalTo: newStream)
            throw error
        }
    }
    
    /// 停止屏幕采集
    func stopCapture() async throws {
        guard let currentStream = takeStream() else {
            return
        }
        try await currentStream.stopCapture()
    }
    
    
    // MARK: - 工具
    
    var isCapturing: Bool {
        hasStream()
    }
    
    private func hasStream() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stream != nil
    }
    
    private func installStream(_ newStream: SCStream) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard stream == nil else {
            return false
        }
        
        stream = newStream
        return true
    }
    
    private func clearStream(ifIdenticalTo target: SCStream) {
        lock.lock()
        defer { lock.unlock() }
        
        if stream === target {
            stream = nil
        }
    }
    
    private func takeStream() -> SCStream? {
        lock.lock()
        defer { lock.unlock() }
        
        let current = stream
        stream = nil
        return current
    }
    
    // MARK: - 回调
    
    private func emitFrame(_ frame: CapturedFrame) {
        lock.lock()
        let handler = frameHandler
        lock.unlock()
        
        handler?(frame)
    }
    
    private func emitError(_ error: Error) {
        lock.lock()
        let handler = errorHandler
        lock.unlock()
        
        handler?(error)
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else {
            return
        }
        
        guard CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
        emitFrame(frame)
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.lock()
        if self.stream == stream {
            self.stream = nil
        }
        lock.unlock()
        emitError(error)
    }
}

extension ScreenCaptureManager {
    struct Configuration: Sendable {
        /// 目标帧率
        var framesPerSecond: Int = 20
        
        /// 输出分辨率缩放倍率
        var scaleFactor: Double = 1.0
        
        /// Stream 缓冲队列深度
        var queueDepth: Int = 5
        
        /// 是否显示鼠标指针
        var showsCursor: Bool = false
    }
}
