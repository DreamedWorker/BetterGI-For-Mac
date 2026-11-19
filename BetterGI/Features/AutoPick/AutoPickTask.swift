//
//  AutoPickTask.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore

/// 自动拾取在一帧上的结果。
nonisolated enum AutoPickOutcome: Equatable, Sendable {
    enum SkipReason: Equatable, Sendable {
        /// 物品图标是设置图标（解谜、电梯、活动等交互）
        case settingsIcon
        /// 千星奇遇中（画面右侧有 L 键提示）
        case miliastra
        /// 名称不在白名单中；`itemName` 为 nil 表示没识别到名称
        case notAllowed(itemName: String?)
        /// 需要白名单但文字识别失败
        case nameUnavailable
        /// 开启名称识别但白名单为空
        case whitelistEmpty
    }

    /// 自动拾取已关闭
    case disabled
    /// 识别资源加载失败
    case assetsUnavailable(String?)
    /// 还没有定位到游戏画面
    case noViewport
    /// 画面中没有拾取提示
    case searching
    /// 有拾取提示，但游戏窗口不在前台，不发送按键
    case waitingForFocus
    /// 刚按过拾取键，等待间隔结束
    case coolingDown
    /// 有拾取提示，但按规则不拾取
    case skipped(SkipReason)
    /// 已发送拾取键
    case picked(itemName: String?)
    /// 没有辅助功能权限，无法发送按键
    case inputUnavailable
}

/// 处理队列发布、主线程定时读取的自动拾取状态。
nonisolated struct AutoPickSnapshot: Equatable, Sendable {
    var outcome: AutoPickOutcome = .disabled
    var score: Double?
    var pickCount = 0
    var lastPickedItem: String?
}

nonisolated final class AutoPickReport: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = AutoPickSnapshot()

    var current: AutoPickSnapshot {
        lock.withLock { snapshot }
    }

    func update(outcome: AutoPickOutcome, score: Double?) {
        lock.withLock {
            snapshot.outcome = outcome
            snapshot.score = score

            if case .picked(let itemName) = outcome {
                snapshot.pickCount += 1
                snapshot.lastPickedItem = itemName
            }
        }
    }

    func reset() {
        lock.withLock {
            snapshot = AutoPickSnapshot()
        }
    }
}

/// 自动拾取：发现拾取提示（F 键图标）时识别物品名称，命中白名单就按下 F。
nonisolated final class AutoPickTask: GameFrameConsumer {
    /// 一帧画面中与拾取提示相关的识别结果。
    private struct Inspection: Sendable {
        let match: PickPromptLocator.Match
        /// 匹配度达到阈值且通过结构校验，确认是拾取提示
        let isPrompt: Bool
        let showsMiliastraKey: Bool
        let showsSettingsIcon: Bool
    }

    /// 两次按键的最小间隔。拾取后提示列表会刷新，间隔太短容易按到下一项之前的过渡画面。
    private let minimumPressInterval: TimeInterval = 0.15

    /// 同一位置的名称识别结果在这段时间内复用，避免停在不拾取物品旁时每帧都做文字识别。
    private let nameCacheLifetime: TimeInterval = 1.0

    private let settingsStore: AutoPickSettingsStore
    private let target: GameWindowTarget
    private let focusMonitor: FrontmostAppMonitor
    private let report: AutoPickReport
    private let bundle: Bundle
    private let nameRecognizer = ItemNameRecognizer()

    /// 识别资源在首次启用时懒加载；`didAttemptAssetLoad` 避免加载失败后每帧重试。
    private var locator: PickPromptLocator?
    private var didAttemptAssetLoad = false
    private var assetError: String?

    private var lastPressTime: TimeInterval = -.infinity
    private var cachedName: (keyRect: CGRect, name: String?, time: TimeInterval)?

    init(
        settingsStore: AutoPickSettingsStore,
        target: GameWindowTarget,
        focusMonitor: FrontmostAppMonitor,
        report: AutoPickReport,
        bundle: Bundle = .main
    ) {
        self.settingsStore = settingsStore
        self.target = target
        self.focusMonitor = focusMonitor
        self.report = report
        self.bundle = bundle
    }

    func process(
        frame: CapturedFrame,
        viewport: CGRect?,
        now: TimeInterval
    ) throws {
        let settings = settingsStore.current

        guard settings.isEnabled else {
            cachedName = nil
            report.update(outcome: .disabled, score: nil)
            return
        }

        guard let viewport else {
            report.update(outcome: .noViewport, score: nil)
            return
        }

        // 白名单为空时不加载模板，也不执行匹配。
        if settings.recognizesItemName, settings.allowedKeywords.isEmpty {
            report.update(outcome: .skipped(.whitelistEmpty), score: nil)
            return
        }

        ensureAssetsLoaded()

        guard let locator else {
            report.update(outcome: .assetsUnavailable(assetError), score: nil)
            return
        }

        let inspection = try BGRAFrame.withLocked(frame.pixelBuffer) { buffer -> Inspection? in
            guard let match = locator.locate(in: buffer, viewport: viewport) else {
                return nil
            }

            let isPrompt = match.score >= settings.matchThreshold && match.hasGlyphStructure
            guard isPrompt else {
                return Inspection(
                    match: match,
                    isPrompt: false,
                    showsMiliastraKey: false,
                    showsSettingsIcon: false
                )
            }

            return Inspection(
                match: match,
                isPrompt: true,
                showsMiliastraKey: locator.showsMiliastraKey(in: buffer, viewport: viewport),
                showsSettingsIcon: locator.showsSettingsIcon(in: buffer, nextTo: match)
            )
        }

        resolve(
            inspection,
            settings: settings,
            pixelBuffer: frame.pixelBuffer,
            now: now
        )
    }

    // MARK: - 识别资源

    private func ensureAssetsLoaded() {
        guard !didAttemptAssetLoad else { return }
        didAttemptAssetLoad = true

        do {
            let assets = try AutoPickAssets(bundle: bundle)
            locator = PickPromptLocator(assets: assets)
        } catch {
            assetError = error.localizedDescription
        }
    }

    // MARK: - 决策

    private func resolve(
        _ inspection: Inspection?,
        settings: AutoPickSettings,
        pixelBuffer: CVPixelBuffer,
        now: TimeInterval
    ) {
        guard let inspection else {
            report.update(outcome: .searching, score: nil)
            return
        }

        let match = inspection.match
        guard inspection.isPrompt else {
            report.update(outcome: .searching, score: match.score)
            return
        }

        guard GameWindowFocus.isFocused(
            target,
            frontmostProcessID: focusMonitor.frontmostProcessID
        ) else {
            report.update(outcome: .waitingForFocus, score: match.score)
            return
        }

        if inspection.showsMiliastraKey {
            report.update(outcome: .skipped(.miliastra), score: match.score)
            return
        }

        if inspection.showsSettingsIcon {
            report.update(outcome: .skipped(.settingsIcon), score: match.score)
            return
        }

        guard CACurrentMediaTime() - lastPressTime >= minimumPressInterval else {
            report.update(outcome: .coolingDown, score: match.score)
            return
        }

        var itemName: String?
        if settings.recognizesItemName {
            // 白名单模式下必须至少配置一个关键词；关闭名称识别才会退化为“拾取全部”。
            guard !settings.allowedKeywords.isEmpty else {
                report.update(
                    outcome: .skipped(.whitelistEmpty),
                    score: match.score
                )
                return
            }

            itemName = recognizeName(for: match, in: pixelBuffer, now: now)

            guard let itemName else {
                report.update(
                    outcome: .skipped(.nameUnavailable),
                    score: match.score
                )
                return
            }

            guard settings.allowedKeyword(in: itemName) != nil else {
                report.update(
                    outcome: .skipped(.notAllowed(itemName: itemName)),
                    score: match.score
                )
                return
            }
        }

        guard KeySimulator.tap(KeySimulator.keyF) else {
            report.update(outcome: .inputUnavailable, score: match.score)
            return
        }

        lastPressTime = CACurrentMediaTime()
        // 拾取后列表会变化，同一位置可能换成另一件物品，必须重新识别。
        cachedName = nil
        report.update(outcome: .picked(itemName: itemName), score: match.score)
    }

    private func recognizeName(
        for match: PickPromptLocator.Match,
        in pixelBuffer: CVPixelBuffer,
        now: TimeInterval
    ) -> String? {
        if let cachedName,
           now - cachedName.time < nameCacheLifetime,
           abs(cachedName.keyRect.minY - match.keyRect.minY) < match.keyRect.height * 0.25 {
            return cachedName.name
        }

        typealias Layout = PickPromptLocator.RowLayout
        let scale = match.gameScale
        let textRect = CGRect(
            x: match.keyRect.minX + Layout.nameLeft * scale,
            y: match.keyRect.minY - Layout.verticalPadding * scale,
            width: (Layout.nameRight - Layout.nameLeft) * scale,
            height: match.keyRect.height + Layout.verticalPadding * 2 * scale
        )
        let name = nameRecognizer.recognize(in: pixelBuffer, rect: textRect)
        cachedName = (match.keyRect, name, now)
        return name
    }
}
