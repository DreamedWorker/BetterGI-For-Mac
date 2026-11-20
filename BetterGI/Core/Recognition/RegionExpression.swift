//
//  RegionExpression.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation

nonisolated enum RegionExpressionError: LocalizedError, Equatable {
    case unsupported(String)
    case invalidSyntax(String, reason: String)
    case cyclicVariable(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let source):
            return "不支持的区域写法「\(source)」，目前支持 rect(x, y, width, height) 以及按比例裁剪画布的 cutLeft/cutRight/cutTop/cutBottom/cutLeftTop/cutRightTop/cutLeftBottom/cutRightBottom"
        case .invalidSyntax(let source, let reason):
            return "区域表达式「\(source)」有误：\(reason)"
        case .cyclicVariable(let name):
            return "变量「\(name)」存在循环引用"
        }
    }
}

/// Recognition.json 中 `roi`、`reference.bbox`、`search.box` 等字段的矩形表达式。
///
/// 支持：
/// - 返回矩形的函数 `rect(x, y, width, height)`；
/// - 按比例裁剪当前画布的 `cutLeft(0.2)`、`cutRightTop(0.3, 0.2)` 等函数，比例以 0...1 表示；
/// - 四则运算、括号与取负；
/// - 变量 `s`（缩放比例）、`cw` / `ch`（画布宽高）、`cx` / `cy`（画布左上角坐标），
///   以及 `variables` 中自定义的变量。自定义变量的值是算式，可以引用其它变量。
///
/// 计算结果是相对画布左上角的矩形（像素）。
nonisolated struct RegionExpression: Sendable {
    let source: String
    private let root: RectNode
    private let variables: [String: Node]

    init(_ source: String, variables: [String: String] = [:]) throws {
        self.source = source

        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw RegionExpressionError.invalidSyntax(source, reason: "表达式为空")
        }

        let customNames = Set(variables.keys)
        var parsedVariables: [String: Node] = [:]
        for (name, expression) in variables {
            var parser = try Parser(expression, source: source, allowedVariables: customNames)
            parsedVariables[name] = try parser.parseNumericExpression()
            try parser.ensureEnd()
        }
        try Self.checkVariableCycles(parsedVariables)

        var parser = try Parser(trimmed, source: source, allowedVariables: customNames)
        let root = try parser.parseRectExpression()
        try parser.ensureEnd()

        self.root = root
        self.variables = parsedVariables
    }

    func evaluate(scale: Double, width: Double, height: Double) -> CGRect {
        evaluate(scale: scale, originX: 0, originY: 0, width: width, height: height)
    }

    /// - Parameters:
    ///   - scale: 表达式中的 `s`
    ///   - originX / originY: 表达式中的 `cx` / `cy`
    ///   - width / height: 表达式中的 `cw` / `ch`
    func evaluate(
        scale: Double,
        originX: Double,
        originY: Double,
        width: Double,
        height: Double
    ) -> CGRect {
        let evaluator = Evaluator(
            scale: scale,
            originX: originX,
            originY: originY,
            width: width,
            height: height,
            variables: variables
        )
        return evaluator.rectangle(root)
    }

    /// 检查自定义变量之间是否存在循环引用。
    private static func checkVariableCycles(_ variables: [String: Node]) throws {
        var state: [String: Int] = [:]

        func visit(_ name: String) throws {
            if state[name] == 2 {
                return
            }
            if state[name] == 1 {
                throw RegionExpressionError.cyclicVariable(name)
            }

            state[name] = 1
            if let node = variables[name] {
                for dependency in referencedVariables(in: node) where variables[dependency] != nil {
                    try visit(dependency)
                }
            }
            state[name] = 2
        }

        for name in variables.keys {
            try visit(name)
        }
    }

    private static func referencedVariables(in node: Node) -> Set<String> {
        switch node {
        case .number:
            return []
        case .variable(let name):
            return [name]
        case .negate(let node):
            return referencedVariables(in: node)
        case .binary(_, let lhs, let rhs):
            return referencedVariables(in: lhs).union(referencedVariables(in: rhs))
        }
    }
}

// MARK: - 语法树

nonisolated private indirect enum Node: Sendable {
    case number(Double)
    case variable(String)
    case negate(Node)
    case binary(Character, Node, Node)
}

nonisolated private indirect enum RectNode: Sendable {
    case rect([Node])
    case cut(CutKind, [Node])
}

nonisolated private enum CutKind: Sendable {
    case left
    case right
    case top
    case bottom
    case leftTop
    case rightTop
    case leftBottom
    case rightBottom

    init?(functionName: String) {
        switch functionName {
        case "cutLeft": self = .left
        case "cutRight": self = .right
        case "cutTop": self = .top
        case "cutBottom": self = .bottom
        case "cutLeftTop": self = .leftTop
        case "cutRightTop": self = .rightTop
        case "cutLeftBottom": self = .leftBottom
        case "cutRightBottom": self = .rightBottom
        default: return nil
        }
    }

    var argumentCount: Int {
        switch self {
        case .left, .right, .top, .bottom:
            return 1
        case .leftTop, .rightTop, .leftBottom, .rightBottom:
            return 2
        }
    }
}

// MARK: - 求值

nonisolated private struct Evaluator {
    let scale: Double
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
    let variables: [String: Node]

    func value(of node: Node) -> Double {
        switch node {
        case .number(let value):
            return value
        case .variable(let name):
            switch name {
            case "s":
                return scale
            case "cw":
                return width
            case "ch":
                return height
            case "cx":
                return originX
            case "cy":
                return originY
            default:
                guard let variable = variables[name] else { return 0 }
                return value(of: variable)
            }
        case .negate(let node):
            return -value(of: node)
        case .binary(let op, let lhs, let rhs):
            let a = value(of: lhs)
            let b = value(of: rhs)
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            default: return b == 0 ? 0 : a / b
            }
        }
    }

    func rectangle(_ node: RectNode) -> CGRect {
        switch node {
        case .rect(let arguments):
            return CGRect(
                x: value(of: arguments[0]),
                y: value(of: arguments[1]),
                width: value(of: arguments[2]),
                height: value(of: arguments[3])
            )
        case .cut(let kind, let arguments):
            return cut(kind, arguments.map(value(of:)))
        }
    }

    /// 比例是裁剪后的占比，结果从画布左上角算起。
    private func cut(_ kind: CutKind, _ values: [Double]) -> CGRect {
        switch kind {
        case .left:
            return CGRect(x: 0, y: 0, width: truncated(width * values[0]), height: height)
        case .right:
            return CGRect(
                x: truncated(width * (1 - values[0])),
                y: 0,
                width: truncated(width * values[0]),
                height: height
            )
        case .top:
            return CGRect(x: 0, y: 0, width: width, height: truncated(height * values[0]))
        case .bottom:
            return CGRect(
                x: 0,
                y: truncated(height * (1 - values[0])),
                width: width,
                height: truncated(height * values[0])
            )
        case .leftTop:
            return CGRect(
                x: 0,
                y: 0,
                width: truncated(width * values[0]),
                height: truncated(height * values[1])
            )
        case .rightTop:
            return CGRect(
                x: truncated(width * (1 - values[0])),
                y: 0,
                width: truncated(width * values[0]),
                height: truncated(height * values[1])
            )
        case .leftBottom:
            return CGRect(
                x: 0,
                y: truncated(height * (1 - values[1])),
                width: truncated(width * values[0]),
                height: truncated(height * values[1])
            )
        case .rightBottom:
            return CGRect(
                x: truncated(width * (1 - values[0])),
                y: truncated(height * (1 - values[1])),
                width: truncated(width * values[0]),
                height: truncated(height * values[1])
            )
        }
    }

    /// 用 (int) 截断。
    private func truncated(_ value: Double) -> Double {
        value.rounded(.towardZero)
    }
}

// MARK: - 解析

/// 递归下降解析：expression = term (('+' | '-') term)*；term = factor (('*' | '/') factor)*。
nonisolated private struct Parser {
    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case symbol(Character)
    }

    private static let builtinVariables: Set<String> = ["s", "cw", "ch", "cx", "cy"]
    private static let builtinVariableList = ["s", "cw", "ch", "cx", "cy"]

    private let source: String
    private let tokens: [Token]
    private let allowedVariables: Set<String>
    private var index = 0

    init(_ text: String, source: String, allowedVariables: Set<String>) throws {
        self.source = source
        self.allowedVariables = allowedVariables

        var tokens: [Token] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let character = text[cursor]
            if character.isWhitespace {
                cursor = text.index(after: cursor)
            } else if character.isNumber || character == "." {
                let end = text[cursor...].firstIndex { !($0.isNumber || $0 == ".") } ?? text.endIndex
                guard let value = Double(text[cursor..<end]) else {
                    throw RegionExpressionError.invalidSyntax(source, reason: "无法识别的数字「\(text[cursor..<end])」")
                }
                tokens.append(.number(value))
                cursor = end
            } else if character.isLetter || character == "_" {
                let end = text[cursor...].firstIndex { !($0.isLetter || $0.isNumber || $0 == "_") } ?? text.endIndex
                tokens.append(.identifier(String(text[cursor..<end])))
                cursor = end
            } else if "+-*/(),".contains(character) {
                tokens.append(.symbol(character))
                cursor = text.index(after: cursor)
            } else {
                throw RegionExpressionError.invalidSyntax(source, reason: "无法识别的字符「\(character)」")
            }
        }
        self.tokens = tokens
    }

    /// 解析整个表达式，结果必须是矩形。
    mutating func parseRectExpression() throws -> RectNode {
        guard index < tokens.count else {
            throw RegionExpressionError.invalidSyntax(source, reason: "表达式不完整")
        }
        guard case .identifier(let functionName) = tokens[index] else {
            throw RegionExpressionError.unsupported(source)
        }
        index += 1

        guard consume(.symbol("(")) else {
            throw RegionExpressionError.unsupported(source)
        }

        var arguments: [Node] = []
        if !isNext(.symbol(")")) {
            arguments.append(try parseNumericExpression())
            while consume(.symbol(",")) {
                arguments.append(try parseNumericExpression())
            }
        }

        guard consume(.symbol(")")) else {
            throw RegionExpressionError.invalidSyntax(source, reason: "括号不匹配")
        }

        if functionName == "rect" {
            guard arguments.count == 4 else {
                throw RegionExpressionError.invalidSyntax(
                    source,
                    reason: "rect 需要 4 个参数，实际为 \(arguments.count) 个"
                )
            }
            return .rect(arguments)
        }

        guard let kind = CutKind(functionName: functionName) else {
            throw RegionExpressionError.unsupported(source)
        }
        guard arguments.count == kind.argumentCount else {
            throw RegionExpressionError.invalidSyntax(
                source,
                reason: "\(functionName) 需要 \(kind.argumentCount) 个参数，实际为 \(arguments.count) 个"
            )
        }
        return .cut(kind, arguments)
    }

    mutating func parseNumericExpression() throws -> Node {
        var node = try parseTerm()
        while let op = consumeSymbol(in: "+-") {
            node = .binary(op, node, try parseTerm())
        }
        return node
    }

    mutating func ensureEnd() throws {
        guard index == tokens.count else {
            throw RegionExpressionError.invalidSyntax(source, reason: "表达式末尾有多余内容")
        }
    }

    private mutating func parseTerm() throws -> Node {
        var node = try parseFactor()
        while let op = consumeSymbol(in: "*/") {
            node = .binary(op, node, try parseFactor())
        }
        return node
    }

    private mutating func parseFactor() throws -> Node {
        guard index < tokens.count else {
            throw RegionExpressionError.invalidSyntax(source, reason: "表达式不完整")
        }

        let token = tokens[index]
        index += 1

        switch token {
        case .number(let value):
            return .number(value)
        case .identifier(let name):
            guard Self.builtinVariables.contains(name) || allowedVariables.contains(name) else {
                var names = Self.builtinVariableList
                names.append(contentsOf: allowedVariables.sorted())
                throw RegionExpressionError.invalidSyntax(
                    source,
                    reason: "未知变量「\(name)」，可用变量为 \(names.joined(separator: "、"))"
                )
            }
            return .variable(name)
        case .symbol("-"):
            return .negate(try parseFactor())
        case .symbol("("):
            let node = try parseNumericExpression()
            guard consume(.symbol(")")) else {
                throw RegionExpressionError.invalidSyntax(source, reason: "括号不匹配")
            }
            return node
        case .symbol(let symbol):
            throw RegionExpressionError.invalidSyntax(source, reason: "意外的符号「\(symbol)」")
        }
    }

    private mutating func consume(_ token: Token) -> Bool {
        guard index < tokens.count, tokens[index] == token else { return false }
        index += 1
        return true
    }

    private func isNext(_ token: Token) -> Bool {
        index < tokens.count && tokens[index] == token
    }

    private mutating func consumeSymbol(in symbols: String) -> Character? {
        guard index < tokens.count, case .symbol(let symbol) = tokens[index], symbols.contains(symbol) else {
            return nil
        }
        index += 1
        return symbol
    }
}
