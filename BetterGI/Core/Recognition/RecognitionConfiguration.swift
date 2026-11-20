//
//  RecognitionConfiguration.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import CoreGraphics
import Foundation

nonisolated enum RecognitionConfigurationError: LocalizedError, Equatable {
    case invalidJSON(String, reason: String)
    case missingObjectType(String)
    case missingTemplate(String)
    case missingTemplateAlias(String, object: String)
    case cyclicTemplateAlias(String, object: String)
    case missingRegionAlias(String, object: String)
    case cyclicRegionAlias(String, object: String)
    case invalidValue(String, field: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let source, let reason):
            return "\(source) 解析失败：\(reason)"
        case .missingObjectType(let object):
            return "识别对象「\(object)」缺少 type"
        case .missingTemplate(let object):
            return "识别对象「\(object)」是 TemplateMatch，但没有配置 template"
        case .missingTemplateAlias(let alias, let object):
            return "识别对象「\(object)」引用的模板别名「@\(alias)」不存在"
        case .cyclicTemplateAlias(let alias, let object):
            return "识别对象「\(object)」的模板别名「@\(alias)」存在循环引用"
        case .missingRegionAlias(let alias, let object):
            return "识别对象「\(object)」引用的区域别名「@\(alias)」不存在"
        case .cyclicRegionAlias(let alias, let object):
            return "识别对象「\(object)」的区域别名「@\(alias)」存在循环引用"
        case .invalidValue(let object, let field, let reason):
            return "识别对象「\(object)」的 \(field) 无效：\(reason)"
        }
    }
}

// 不认识的类型保留原文，避免旧版本直接拒绝整个配置。
nonisolated enum RecognitionObjectType: Sendable, Equatable {
    case templateMatch
    case colorMatch
    case ocrMatch
    case ocr
    case colorRangeAndOcr
    case detect
    case other(String)

    init(_ rawValue: String) {
        switch rawValue {
        case "TemplateMatch": self = .templateMatch
        case "ColorMatch": self = .colorMatch
        case "OcrMatch": self = .ocrMatch
        case "Ocr": self = .ocr
        case "ColorRangeAndOcr": self = .colorRangeAndOcr
        case "Detect": self = .detect
        default: self = .other(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .templateMatch: return "TemplateMatch"
        case .colorMatch: return "ColorMatch"
        case .ocrMatch: return "OcrMatch"
        case .ocr: return "Ocr"
        case .colorRangeAndOcr: return "ColorRangeAndOcr"
        case .detect: return "Detect"
        case .other(let rawValue): return rawValue
        }
    }
}

/// 参考画布的锚定方式。
nonisolated enum SearchAnchorMode: String, Sendable, CaseIterable {
    case auto = "Auto"
    case topLeft = "TopLeft"
    case topRight = "TopRight"
    case bottomLeft = "BottomLeft"
    case bottomRight = "BottomRight"
    case center = "Center"
}

/// 搜索区域四边的扩展比例，顺序：左、上、右、下。
nonisolated struct ExpandPercent: Sendable, Equatable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    init(values: [Double], object: String) throws {
        let left: Double
        let top: Double
        let right: Double
        let bottom: Double

        switch values.count {
        case 1:
            left = values[0]
            top = values[0]
            right = values[0]
            bottom = values[0]
        case 2:
            left = values[0]
            right = values[0]
            top = values[1]
            bottom = values[1]
        case 4:
            left = values[0]
            top = values[1]
            right = values[2]
            bottom = values[3]
        default:
            throw RecognitionConfigurationError.invalidValue(
                object,
                field: "search.expandPercent",
                reason: "需要 1、2 或 4 个数字，实际为 \(values.count) 个"
            )
        }

        let sides = [left, top, right, bottom]
        guard sides.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw RecognitionConfigurationError.invalidValue(
                object,
                field: "search.expandPercent",
                reason: "每个值都必须是有限且非负的数字"
            )
        }

        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

/// Recognition.json 中的一个识别对象。
nonisolated struct RecognitionObject: Sendable {
    /// 模板来源画布与模板在画布中的位置。
    nonisolated struct Reference: Sendable {
        /// 模板来源画布尺寸，例如 1920 × 1080；未配置时为 nil。
        let size: CGSize?
        /// 模板在来源画布中的包围盒；未配置时为 nil。
        let bbox: RegionExpression?
    }

    /// 参考画布锚定搜索配置。
    nonisolated struct Search: Sendable {
        let anchor: SearchAnchorMode
        /// 参考画布坐标系中的搜索框；未配置时用 `reference.bbox`。
        let box: RegionExpression?
        /// 搜索框四周额外扩展的像素，默认 10 × 10。
        let expand: CGSize
        /// 按当前截图宽高计算的扩展比例，优先于 `expand`。
        let expandPercent: ExpandPercent?
    }

    /// objects 下的对象名。
    let name: String
    /// 可选的 name 字段，用于调试绘制时的名字。
    let configuredName: String?
    let type: RecognitionObjectType
    /// 模板文件名或相对路径，已解析 `@模板别名`。
    let template: String?
    let templateMode: String?
    let roi: RegionExpression?

    // MARK: 模板匹配

    let threshold: Double
    let use3Channels: Bool
    let templateMatchMode: String
    let useMask: Bool
    let maskColor: String?
    let maxMatchCount: Int
    let useBinaryMatch: Bool
    let binaryThreshold: Int

    // MARK: 颜色匹配

    let colorCode: String?
    let lowerColor: [Double]
    let upperColor: [Double]
    let matchCount: Int

    // MARK: OCR

    let ocrEngine: String?
    let replace: [String: [String]]
    let allContains: [String]
    let oneContains: [String]
    let regex: [String]
    let text: String?

    // MARK: 调试

    let draw: Bool
    let drawColor: String?
    let drawWidth: Double?

    // MARK: 参考画布与搜索

    let reference: Reference?
    let search: Search?
}

/// Recognition.json（version 1）的完整配置。
///
/// 只解析与校验，不执行识别。
nonisolated struct RecognitionConfiguration: Sendable {
    let version: Int
    let objects: [String: RecognitionObject]

    /// - Parameter source: 出错时展示的文件路径。
    static func parse(data: Data, source: String) throws -> RecognitionConfiguration {
        let raw: RawFile
        do {
            raw = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw RecognitionConfigurationError.invalidJSON(source, reason: error.localizedDescription)
        }

        let variables = raw.vars ?? [:]
        let regions = raw.regions ?? [:]
        let templates = raw.templates ?? [:]

        var objects: [String: RecognitionObject] = [:]
        for (name, object) in raw.objects ?? [:] {
            objects[name] = try build(
                name: name,
                raw: object,
                variables: variables,
                regions: regions,
                templates: templates
            )
        }

        return RecognitionConfiguration(version: raw.version ?? 1, objects: objects)
    }

    // MARK: - 构建

    private static let templateMatchModes: Set<String> = [
        "SqDiff", "SqDiffNormed", "CCorr", "CCorrNormed", "CCoeff", "CCoeffNormed"
    ]

    private static func build(
        name: String,
        raw: RawObject,
        variables: [String: String],
        regions: [String: String],
        templates: [String: String]
    ) throws -> RecognitionObject {
        guard let rawType = raw.type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else {
            throw RecognitionConfigurationError.missingObjectType(name)
        }

        let type = RecognitionObjectType(rawType)
        let template = try resolveAlias(raw.template, table: templates, kind: .template, object: name)

        if type == .templateMatch, template == nil {
            throw RecognitionConfigurationError.missingTemplate(name)
        }

        let roi = try makeRegion(raw.roi, field: "roi", object: name, regions: regions, variables: variables)
        let reference = try makeReference(
            raw.reference,
            object: name,
            regions: regions,
            variables: variables
        )
        let search = try makeSearch(
            raw.search,
            object: name,
            regions: regions,
            variables: variables
        )

        let threshold = raw.threshold ?? 0.8
        guard threshold.isFinite else {
            throw RecognitionConfigurationError.invalidValue(
                name,
                field: "threshold",
                reason: "必须是有限数字"
            )
        }

        let templateMatchMode = try validatedTemplateMatchMode(raw.templateMatchMode, object: name)

        return RecognitionObject(
            name: name,
            configuredName: raw.name,
            type: type,
            template: template,
            templateMode: raw.templateMode,
            roi: roi,
            threshold: threshold,
            use3Channels: raw.use3Channels ?? false,
            templateMatchMode: templateMatchMode,
            useMask: raw.useMask ?? false,
            maskColor: raw.maskColor,
            maxMatchCount: raw.maxMatchCount ?? -1,
            useBinaryMatch: raw.useBinaryMatch ?? false,
            binaryThreshold: raw.binaryThreshold ?? 128,
            colorCode: raw.colorCode,
            lowerColor: raw.lowerColor ?? [],
            upperColor: raw.upperColor ?? [],
            matchCount: raw.matchCount ?? 1,
            ocrEngine: raw.ocrEngine,
            replace: raw.replace ?? [:],
            allContains: raw.allContains ?? [],
            oneContains: raw.oneContains ?? [],
            regex: raw.regex ?? [],
            text: raw.text,
            draw: raw.draw ?? false,
            drawColor: raw.drawColor,
            drawWidth: raw.drawWidth,
            reference: reference,
            search: search
        )
    }

    private static func validatedTemplateMatchMode(_ rawValue: String?, object: String) throws -> String {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "CCoeffNormed"
        }
        guard templateMatchModes.contains(value) else {
            throw RecognitionConfigurationError.invalidValue(
                object,
                field: "templateMatchMode",
                reason: "未知的模板匹配算法「\(value)」，可用值为 \(templateMatchModes.sorted().joined(separator: "、"))"
            )
        }
        return value
    }

    private static func makeReference(
        _ raw: RawReference?,
        object: String,
        regions: [String: String],
        variables: [String: String]
    ) throws -> RecognitionObject.Reference? {
        guard let raw else { return nil }

        var size: CGSize?
        if let values = raw.size {
            guard values.count == 2, values[0] > 0, values[1] > 0 else {
                throw RecognitionConfigurationError.invalidValue(
                    object,
                    field: "reference.size",
                    reason: "需要 [width, height] 两个正整数"
                )
            }
            size = CGSize(width: CGFloat(values[0]), height: CGFloat(values[1]))
        }

        let bbox = try makeRegion(
            raw.bbox,
            field: "reference.bbox",
            object: object,
            regions: regions,
            variables: variables
        )
        return RecognitionObject.Reference(size: size, bbox: bbox)
    }

    private static func makeSearch(
        _ raw: RawSearch?,
        object: String,
        regions: [String: String],
        variables: [String: String]
    ) throws -> RecognitionObject.Search? {
        guard let raw else { return nil }

        let anchor: SearchAnchorMode
        if let rawAnchor = raw.anchor?.trimmingCharacters(in: .whitespacesAndNewlines), !rawAnchor.isEmpty {
            guard let parsed = SearchAnchorMode(rawValue: rawAnchor) else {
                throw RecognitionConfigurationError.invalidValue(
                    object,
                    field: "search.anchor",
                    reason: "未知的锚点「\(rawAnchor)」，可用值为 \(SearchAnchorMode.allCases.map(\.rawValue).joined(separator: "、"))"
                )
            }
            anchor = parsed
        } else {
            anchor = .auto
        }

        let box = try makeRegion(
            raw.box,
            field: "search.box",
            object: object,
            regions: regions,
            variables: variables
        )

        var expand = CGSize(width: 10, height: 10)
        if let values = raw.expand {
            guard values.count == 2, values[0] >= 0, values[1] >= 0 else {
                throw RecognitionConfigurationError.invalidValue(
                    object,
                    field: "search.expand",
                    reason: "需要 [width, height] 两个非负整数"
                )
            }
            expand = CGSize(width: CGFloat(values[0]), height: CGFloat(values[1]))
        }

        let expandPercent = try raw.expandPercent.map {
            try ExpandPercent(values: $0, object: object)
        }

        return RecognitionObject.Search(
            anchor: anchor,
            box: box,
            expand: expand,
            expandPercent: expandPercent
        )
    }

    private static func makeRegion(
        _ value: String?,
        field: String,
        object: String,
        regions: [String: String],
        variables: [String: String]
    ) throws -> RegionExpression? {
        guard let resolved = try resolveAlias(value, table: regions, kind: .region, object: object) else {
            return nil
        }

        do {
            return try RegionExpression(resolved, variables: variables)
        } catch {
            throw RecognitionConfigurationError.invalidValue(
                object,
                field: field,
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - 别名

    private enum AliasKind {
        case region
        case template
    }

    /// 解析 `@别名`；只支持整段表达式或模板名的别名。
    private static func resolveAlias(
        _ value: String?,
        table: [String: String],
        kind: AliasKind,
        object: String
    ) throws -> String? {
        guard var resolved = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resolved.isEmpty else {
            return nil
        }

        var seen: Set<String> = []
        while resolved.hasPrefix("@") {
            let alias = String(resolved.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty else {
                throw aliasError(kind: kind, alias: resolved, object: object, cyclic: false)
            }
            guard let next = table[alias]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !next.isEmpty else {
                throw aliasError(kind: kind, alias: alias, object: object, cyclic: false)
            }
            guard seen.insert(alias).inserted else {
                throw aliasError(kind: kind, alias: alias, object: object, cyclic: true)
            }
            resolved = next
        }

        return resolved
    }

    private static func aliasError(
        kind: AliasKind,
        alias: String,
        object: String,
        cyclic: Bool
    ) -> RecognitionConfigurationError {
        switch (kind, cyclic) {
        case (.template, false):
            return .missingTemplateAlias(alias, object: object)
        case (.template, true):
            return .cyclicTemplateAlias(alias, object: object)
        case (.region, false):
            return .missingRegionAlias(alias, object: object)
        case (.region, true):
            return .cyclicRegionAlias(alias, object: object)
        }
    }
}

// MARK: - 原始 JSON 结构

nonisolated private struct RawFile: Decodable {
    let version: Int?
    let vars: [String: String]?
    let regions: [String: String]?
    let templates: [String: String]?
    let objects: [String: RawObject]?
}

nonisolated private struct RawObject: Decodable {
    let name: String?
    let type: String?
    let template: String?
    let templateMode: String?
    let roi: String?
    let threshold: Double?
    let use3Channels: Bool?
    let templateMatchMode: String?
    let useMask: Bool?
    let maskColor: String?
    let draw: Bool?
    let drawColor: String?
    let drawWidth: Double?
    let maxMatchCount: Int?
    let useBinaryMatch: Bool?
    let binaryThreshold: Int?
    let colorCode: String?
    let lowerColor: [Double]?
    let upperColor: [Double]?
    let matchCount: Int?
    let ocrEngine: String?
    let replace: [String: [String]]?
    let allContains: [String]?
    let oneContains: [String]?
    let regex: [String]?
    let text: String?
    let reference: RawReference?
    let search: RawSearch?
}

nonisolated private struct RawReference: Decodable {
    let size: [Int]?
    let bbox: String?
}

nonisolated private struct RawSearch: Decodable {
    let anchor: String?
    let box: String?
    let expand: [Int]?
    let expandPercent: [Double]?
}
