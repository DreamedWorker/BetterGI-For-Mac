//
//  AutoPickSettings.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation

/// 自动拾取的用户设置
nonisolated struct AutoPickSettings: Codable, Equatable, Sendable {
    /// 是否启用自动拾取
    var isEnabled = false

    /// 拾取键模板的最低匹配度（TM_CCOEFF_NORMED）
    var matchThreshold = 0.75

    /// 是否识别物品名称。关闭后不再进行文字识别，白名单也随之失效。
    var recognizesItemName = true

    /// 仅拾取名称包含这些关键词的物品；为空时不拾取任何物品。
    var allowedKeywords: [String] = []

    static let thresholdRange: ClosedRange<Double> = 0.6...0.95

    init() {}

    /// 逐项解码，缺失的字段使用默认值，以便以后新增设置项时旧数据仍能读取。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AutoPickSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        matchThreshold = try container.decodeIfPresent(Double.self, forKey: .matchThreshold) ?? defaults.matchThreshold
        recognizesItemName = try container.decodeIfPresent(Bool.self, forKey: .recognizesItemName) ?? defaults.recognizesItemName
        allowedKeywords = try container.decodeIfPresent([String].self, forKey: .allowedKeywords) ?? defaults.allowedKeywords
    }

    /// 名称命中的第一个白名单关键词。
    func allowedKeyword(in itemName: String) -> String? {
        allowedKeywords.first { itemName.contains($0) }
    }

    /// 把用户输入拆成关键词：支持中英文逗号、顿号、分号、空格和换行分隔，自动去重。
    static func parseKeywords(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，、;；").union(.whitespacesAndNewlines)
        var seen = Set<String>()
        return text
            .components(separatedBy: separators)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// 在主线程修改、在处理队列读取的设置快照。
nonisolated final class AutoPickSettingsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AutoPickSettings

    init(_ settings: AutoPickSettings) {
        self.settings = settings
    }

    var current: AutoPickSettings {
        lock.withLock { settings }
    }

    func update(_ newValue: AutoPickSettings) {
        lock.withLock { settings = newValue }
    }
}

/// 自动拾取设置的持久化入口。
nonisolated enum AutoPickPreferences {
    @Preference("autoPickSettings", defaultValue: AutoPickSettings())
    static var settings: AutoPickSettings
}
