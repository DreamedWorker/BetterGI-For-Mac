//
//  StartupViewModel.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation
import QuartzCore
import ScreenCaptureKit

@Observable
final class StartupViewModel {
    private(set) var logs: [LogEntry] = []
    private(set) var isRecording = false
    private(set) var isBusy = false

    /// 正在录制（或正在启动录制）的窗口标题
    private(set) var recordingWindowTitle: String?

    // MARK: - 处理指标

    private(set) var captureFPS: Double = 0
    private(set) var processingFPS: Double = 0
    private(set) var processingDuration: TimeInterval = 0
    private(set) var droppedFrames: Int = 0

    // MARK: - 自动拾取

    var autoPickSettings: AutoPickSettings = AutoPickPreferences.settings {
        didSet {
            guard autoPickSettings != oldValue else { return }

            AutoPickPreferences.settings = autoPickSettings
            autoPickSettingsStore.update(autoPickSettings)

            if autoPickSettings.isEnabled != oldValue.isEnabled {
                autoPickLogReporter.reset(
                    baselinePickCount: autoPickReport.current.pickCount
                )
                if autoPickSettings.isEnabled {
                    log("已开启自动拾取", level: .info)
                    if isRecording {
                        warnIfInputUnavailable()
                    }
                } else {
                    log("已关闭自动拾取", level: .info)
                }
            }
        }
    }

    @ObservationIgnored private var manager: ScreenCaptureManager?
    @ObservationIgnored private var pipeline: OpenCVFramePipeline?
    @ObservationIgnored private var operationToken = 0

    private let metricsUpdateInterval: TimeInterval = 0.25
    private let maxLogCount = 300

    @ObservationIgnored private var lastCaptureTimestamp: TimeInterval?
    @ObservationIgnored private var captureFrameCount = 0
    @ObservationIgnored private var pendingDroppedFrames = 0

    @ObservationIgnored private var lastProcessingTimestamp: TimeInterval?
    @ObservationIgnored private var processingFrameCount = 0
    @ObservationIgnored private var pendingProcessingDuration: TimeInterval?
    @ObservationIgnored private var pendingAnalysis: FrameAnalysis?
    @ObservationIgnored private var lastMetricsUpdate: TimeInterval = 0

    @ObservationIgnored private var hasReportedProcessingError = false
    @ObservationIgnored private var loggedViewport: CGRect?
    @ObservationIgnored private var recordingStartedAt: TimeInterval = 0
    @ObservationIgnored private var hasWarnedMissingViewport = false

    @ObservationIgnored private let autoPickSettingsStore = AutoPickSettingsStore(AutoPickPreferences.settings)
    @ObservationIgnored private var autoPickReport = AutoPickReport()
    @ObservationIgnored private let autoPickLogReporter = AutoPickLogReporter()
    @ObservationIgnored private let frontmostMonitor = FrontmostAppMonitor()
    @ObservationIgnored private var hasReportedInputUnavailable = false
    @ObservationIgnored private var hasViewport = false

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

    func startRecording(window: SCWindow) async {
        guard !isRecording, !isBusy else { return }

        guard let processID = window.owningApplication?.processID else {
            log("无法确定「\(window.displayTitle)」所属的应用，不能作为操作目标", level: .error)
            return
        }

        operationToken += 1
        let token = operationToken

        isBusy = true
        recordingWindowTitle = window.displayTitle
        log("开始录制「\(window.displayTitle)」…", level: .info)
        resetMetrics()

        guard AppPermission.screenRecording.isGrantedBySystem else {
            isBusy = false
            recordingWindowTitle = nil
            log("缺少屏幕录制权限，无法开始采集", level: .error)
            return
        }

        // 每次录制使用新的报告对象，避免上一轮尚未结束的帧写入新会话状态。
        autoPickReport = AutoPickReport()
        let target = GameWindowTarget(windowID: window.windowID, processID: processID)
        let autoPickTask = AutoPickTask(
            settingsStore: autoPickSettingsStore,
            target: target,
            focusMonitor: frontmostMonitor,
            report: autoPickReport,
            bundle: .main
        )
        let processor = GameFrameProcessor(consumers: [autoPickTask])
        let pipeline = OpenCVFramePipeline(processor: processor) { [weak self] result in
            self?.handleProcessingResult(result, token: token)
        }
        self.pipeline = pipeline

        let configuration = ScreenCaptureManager.Configuration(
            framesPerSecond: 20,
            scaleFactor: Self.captureScale(for: window),
            queueDepth: 3,
            showsCursor: false
        )
        let manager = ScreenCaptureManager(window: window, configuration: configuration)

        manager.onFrame = { [weak self] frame in
            let accepted = pipeline.submit(frame)

            Task { @MainActor [weak self] in
                self?.handleCapturedFrame(accepted: accepted, token: token)
            }
        }
        manager.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleCaptureError(error, token: token)
            }
        }
        self.manager = manager

        do {
            try await manager.startCapture()

            guard token == operationToken else {
                try? await manager.stopCapture()
                return
            }

            recordingStartedAt = CACurrentMediaTime()
            isRecording = true
            isBusy = false
            frontmostMonitor.start()
            log("录制已开始：\(window.displayTitle)", level: .success)
            log("处理管线已就绪，正在定位游戏画面区域", level: .info)

            if autoPickSettings.isEnabled {
                log("自动拾取已开启，将在识别到游戏画面后加载模板", level: .info)
                warnIfInputUnavailable()
            }
        } catch {
            guard token == operationToken else { return }

            self.pipeline = nil
            self.manager = nil
            isRecording = false
            isBusy = false
            recordingWindowTitle = nil
            stopMetrics()
            log("开始录制失败：\(error.localizedDescription)", level: .error)
        }
    }

    func stopRecording(trigger: StopTrigger) {
        guard isRecording, let manager else { return }

        operationToken += 1
        let token = operationToken
        let title = recordingWindowTitle ?? "当前窗口"

        self.manager = nil
        self.pipeline = nil
        isRecording = false
        isBusy = true
        recordingWindowTitle = nil
        frontmostMonitor.stop()
        stopMetrics()

        switch trigger {
        case .user:
            log("正在停止「\(title)」的录制…", level: .info)
        case .selectionChanged:
            log("窗口选择已变更，正在停止「\(title)」的录制…", level: .warning)
        case .viewDisappeared:
            log("主界面已关闭，正在停止「\(title)」的录制…", level: .warning)
        }

        Task {
            do {
                try await manager.stopCapture()

                if token == operationToken {
                    isBusy = false
                    log("录制已停止：\(title)", level: .success)
                }
            } catch {
                if token == operationToken {
                    isBusy = false
                    log("停止录制失败：\(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    /// 切换选择时，录制中的窗口会被停止，但不会自动开始新窗口的录制。
    func handleSelectionChange() {
        if isRecording {
            stopRecording(trigger: .selectionChanged)
        } else if isBusy, manager != nil {
            cancelPendingStart()
        }
    }

    /// 主界面关闭时调用。切换侧边栏页面不会触发，录制会继续进行。
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
        pipeline = nil
        isBusy = false
        recordingWindowTitle = nil
        frontmostMonitor.stop()
        stopMetrics()
        log("已取消进行中的录制启动", level: .warning)
    }

    private func handleCaptureError(_ error: any Error, token: Int) {
        guard token == operationToken else { return }

        operationToken += 1
        manager = nil
        pipeline = nil
        isRecording = false
        isBusy = false
        frontmostMonitor.stop()
        stopMetrics()

        let title = recordingWindowTitle ?? "当前窗口"
        recordingWindowTitle = nil
        log("录制异常（\(title)）：\(error.localizedDescription)", level: .error)
    }

    /// 采集分辨率跟随窗口所在屏幕的像素密度：Retina 屏上按物理像素采集。
    /// 同时限制最长边，避免超大窗口每帧的数据量过大。
    private static func captureScale(for window: SCWindow) -> Double {
        let frame = window.frame
        guard let primaryScreen = NSScreen.screens.first else { return 1 }

        // SCWindow.frame 以主屏左上角为原点，NSScreen.frame 以主屏左下角为原点。
        let cocoaFrame = CGRect(
            x: frame.minX,
            y: primaryScreen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        func overlapArea(_ screen: NSScreen) -> CGFloat {
            let overlap = screen.frame.intersection(cocoaFrame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        let screen = NSScreen.screens.max { overlapArea($0) < overlapArea($1) }
        let backingScale = Double(screen?.backingScaleFactor ?? 1)

        let longestSide = Double(max(frame.width, frame.height))
        guard longestSide > 0 else { return backingScale }
        return max(0.5, min(backingScale, 2560 / longestSide))
    }

    // MARK: - 处理指标

    private func resetMetrics() {
        pipeline = nil
        captureFPS = 0
        processingFPS = 0
        processingDuration = 0
        droppedFrames = 0
        lastCaptureTimestamp = nil
        captureFrameCount = 0
        pendingDroppedFrames = 0
        lastProcessingTimestamp = nil
        processingFrameCount = 0
        pendingProcessingDuration = nil
        pendingAnalysis = nil
        lastMetricsUpdate = 0
        hasReportedProcessingError = false
        hasViewport = false
        loggedViewport = nil
        recordingStartedAt = 0
        hasWarnedMissingViewport = false
        resetAutoPickState()
    }

    private func stopMetrics() {
        pipeline = nil
        captureFPS = 0
        processingFPS = 0
        processingDuration = 0
        lastCaptureTimestamp = nil
        captureFrameCount = 0
        pendingDroppedFrames = 0
        lastProcessingTimestamp = nil
        processingFrameCount = 0
        pendingProcessingDuration = nil
        pendingAnalysis = nil
        lastMetricsUpdate = 0
        hasViewport = false
        loggedViewport = nil
        resetAutoPickState()
    }

    private func handleCapturedFrame(accepted: Bool, token: Int) {
        guard token == operationToken else { return }

        let now = CACurrentMediaTime()
        if lastCaptureTimestamp == nil {
            lastCaptureTimestamp = now
        }
        captureFrameCount += 1

        if !accepted {
            pendingDroppedFrames += 1
        }

        publishMetricsIfNeeded(now: now)
    }

    private func handleProcessingResult(_ result: FrameProcessingResult, token: Int) {
        guard token == operationToken else { return }

        let now = CACurrentMediaTime()
        if lastProcessingTimestamp == nil {
            lastProcessingTimestamp = now
        }
        processingFrameCount += 1

        switch result {
        case .success(let analysis, let duration):
            pendingProcessingDuration = duration
            pendingAnalysis = analysis
            publishMetricsIfNeeded(now: now)

        case .failure(let message):
            guard !hasReportedProcessingError else { return }
            hasReportedProcessingError = true
            log("画面处理失败：\(message)", level: .error)
        }
    }

    /// 将耗时、丢帧、玩法结果等高频指标限制在 4 fps 更新，减少主线程刷新压力。
    private func publishMetricsIfNeeded(now: TimeInterval) {
        guard now - lastMetricsUpdate >= metricsUpdateInterval else { return }
        lastMetricsUpdate = now

        if let start = lastCaptureTimestamp {
            let elapsed = now - start
            if elapsed >= 1.0 {
                captureFPS = Double(captureFrameCount) / elapsed
                lastCaptureTimestamp = now
                captureFrameCount = 0
            }
        }

        if let start = lastProcessingTimestamp {
            let elapsed = now - start
            if elapsed >= 1.0 {
                processingFPS = Double(processingFrameCount) / elapsed
                lastProcessingTimestamp = now
                processingFrameCount = 0
            }
        }

        if let duration = pendingProcessingDuration {
            processingDuration = duration
            pendingProcessingDuration = nil
        }

        if pendingDroppedFrames > 0 {
            droppedFrames += pendingDroppedFrames
            pendingDroppedFrames = 0
        }

        if let analysis = pendingAnalysis {
            pendingAnalysis = nil
            updateViewport(analysis.viewport)
        }

        if autoPickSettings.isEnabled, isRecording {
            for event in autoPickLogReporter.drain(
                autoPickReport.current,
                isEnabled: true
            ) {
                log(event.message, level: event.level)
            }
        }

        if !hasWarnedMissingViewport,
           isRecording,
           recordingStartedAt > 0,
           now - recordingStartedAt > 3,
           !hasViewport {
            hasWarnedMissingViewport = true
            log("还没有找到 16:9 的游戏画面，请确认窗口里显示的是游戏", level: .warning)
        }
    }

    private func updateViewport(_ viewport: CGRect?) {
        hasViewport = viewport != nil
        guard let viewport else { return }

        let isNew = loggedViewport.map { previous in
            abs(previous.minX - viewport.minX) > 2
                || abs(previous.minY - viewport.minY) > 2
                || abs(previous.width - viewport.width) > 2
                || abs(previous.height - viewport.height) > 2
        } ?? true
        guard isNew else { return }

        loggedViewport = viewport
        log(
            "游戏画面区域：\(Int(viewport.width)) × \(Int(viewport.height))，"
                + "位于 (\(Int(viewport.minX)), \(Int(viewport.minY)))",
            level: .info
        )
    }

    // MARK: - 自动拾取

    private func resetAutoPickState() {
        autoPickReport.reset()
        autoPickLogReporter.reset(baselinePickCount: 0)
        hasReportedInputUnavailable = false
    }

    private func warnIfInputUnavailable() {
        guard !hasReportedInputUnavailable, !KeySimulator.canPostEvents else { return }
        hasReportedInputUnavailable = true
        log(
            "没有辅助功能权限，无法发送按键：请在「系统设置 › 隐私与安全性 › 辅助功能」中允许 BetterGI，然后重新打开 App",
            level: .error
        )
    }
}

extension StartupViewModel {
    enum StopTrigger {
        case user
        case selectionChanged
        case viewDisappeared
    }
}
