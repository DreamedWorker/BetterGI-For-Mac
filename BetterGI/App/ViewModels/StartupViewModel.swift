//
//  StartupViewModel.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation
import ScreenCaptureKit

@Observable
final class StartupViewModel {
    private(set) var logs: [LogEntry] = []
    private(set) var isRecording = false
    private(set) var isBusy = false
    
    /// 正在录制（或正在启动录制）的窗口标题
    private(set) var recordingWindowTitle: String?
    
    @ObservationIgnored private var manager: ScreenCaptureManager?
    @ObservationIgnored private var operationToken = 0
    
    // MARK: - 处理指标
    private(set) var captureFPS: Double = 0
    private(set) var processingFPS: Double = 0
    private(set) var processingDuration: TimeInterval = 0
    private(set) var droppedFrames: Int = 0
    
    //@ObservationIgnored private var pipeline: OpenCVFramePipeline?
    @ObservationIgnored private var lastCaptureTimestamp: TimeInterval?
    @ObservationIgnored private var lastProcessingTimestamp: TimeInterval?
    @ObservationIgnored private var captureFrameCount = 0
    @ObservationIgnored private var processingFrameCount = 0
    @ObservationIgnored private var hasReportedProcessingError = false
    
    @ObservationIgnored private var pendingProcessingDuration: TimeInterval?
    @ObservationIgnored private var pendingDroppedFrames = 0
    @ObservationIgnored private var lastMetricsUpdate: TimeInterval = 0
    private let metricsUpdateInterval: TimeInterval = 0.25
    
    private let maxLogCount = 300
    
    // MARK: - 日志
    
    func log(_ message: String, level: LogEntry.Level = .info) {
        logs.append(LogEntry(date: Date(), level: level, message: message))
        
        if logs.count > maxLogCount {
            logs.removeFirst(logs.count - maxLogCount)
        }
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    // MARK: - 录制
    
    func startRecording(window: SCWindow) async {}
    
    func stopRecording(trigger: StopTrigger) {}
    
    func handleSelectionChange() {
        if isRecording {
            stopRecording(trigger: .selectionChanged)
        } else if isBusy, manager != nil {
            // 启动还没完成就换了窗口：取消这次启动，等它完成后自行释放流。
            cancelPendingStart()
        }
    }
    
    func handleDisappearance() {
        if isRecording {
            stopRecording(trigger: .viewDisappeared)
        } else if isBusy, manager != nil {
            cancelPendingStart()
        }
    }
    
    // MARK: - 内部
    
    private func cancelPendingStart() {
        operationToken += 1
        manager = nil
        isBusy = false
        recordingWindowTitle = nil
        stopMetrics()
        log("已取消进行中的录制启动", level: .warning)
    }
    
    private func stopMetrics() {
        //pipeline = nil
        captureFPS = 0
        processingFPS = 0
        lastCaptureTimestamp = nil
        lastProcessingTimestamp = nil
        captureFrameCount = 0
        processingFrameCount = 0
        pendingProcessingDuration = nil
        pendingDroppedFrames = 0
        lastMetricsUpdate = 0
    }
}

extension StartupViewModel {
    enum StopTrigger {
        case user
        case selectionChanged
        case viewDisappeared
    }
}
