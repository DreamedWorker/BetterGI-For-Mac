//
//  RegionExpression.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import Foundation

nonisolated enum RegionExpressionError: LocalizedError {
    case unsupported(String)
    case invalidSyntax(String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let source):
            return "不支持的区域写法「\(source)」，目前只支持 rect(x, y, width, height)"
        case .invalidSyntax(let source, let reason):
            return "区域表达式「\(source)」有误：\(reason)"
        }
    }
}

/// Recognition.json 中 `roi` 字段的表达式，例如 `rect(cw - 110 * s, 550 * s, 70 * s, 100 * s)`。
///
/// 支持数字、括号与四则运算，以及以下变量：
/// - `s`：游戏画面相对 1080p 的缩放比例
/// - `cw` / `ch`：游戏画面的宽 / 高（像素）
///
/// 计算结果是相对游戏画面左上角的矩形（像素）。
nonisolated struct RegionExpression: Sendable {
    let source: String
    private let components: [Node]

    init(_ source: String) throws {
        self.source = source

        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("rect("), trimmed.hasSuffix(")") else {
            throw RegionExpressionError.unsupported(source)
        }

        var parser = try Parser(String(trimmed.dropFirst(5).dropLast()), source: source)
        components = try parser.parseArguments(count: 4)
    }

    func evaluate(scale: Double, width: Double, height: Double) -> CGRect {
        let values = components.map { $0.evaluate(s: scale, cw: width, ch: height) }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}

// MARK: - 语法树

nonisolated private indirect enum Node: Sendable {
    case number(Double)
    case variable(Variable)
    case negate(Node)
    case binary(Character, Node, Node)

    func evaluate(s: Double, cw: Double, ch: Double) -> Double {
        switch self {
        case .number(let value):
            return value
        case .variable(.s):
            return s
        case .variable(.cw):
            return cw
        case .variable(.ch):
            return ch
        case .negate(let node):
            return -node.evaluate(s: s, cw: cw, ch: ch)
        case .binary(let op, let lhs, let rhs):
            let a = lhs.evaluate(s: s, cw: cw, ch: ch)
            let b = rhs.evaluate(s: s, cw: cw, ch: ch)
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            default: return b == 0 ? 0 : a / b
            }
        }
    }
}

nonisolated private enum Variable: String, Sendable {
    case s
    case cw
    case ch
}

// MARK: - 解析

/// 递归下降解析：expression = term (('+' | '-') term)*；term = factor (('*' | '/') factor)*。
nonisolated private struct Parser {
    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case symbol(Character)
    }

    private let source: String
    private let tokens: [Token]
    private var index = 0

    init(_ text: String, source: String) throws {
        self.source = source

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

    mutating func parseArguments(count: Int) throws -> [Node] {
        var arguments = [try parseExpression()]
        while consume(.symbol(",")) {
            arguments.append(try parseExpression())
        }
        guard index == tokens.count else {
            throw RegionExpressionError.invalidSyntax(source, reason: "表达式末尾有多余内容")
        }
        guard arguments.count == count else {
            throw RegionExpressionError.invalidSyntax(source, reason: "需要 \(count) 个参数，实际为 \(arguments.count) 个")
        }
        return arguments
    }

    private mutating func parseExpression() throws -> Node {
        var node = try parseTerm()
        while let op = consumeSymbol(in: "+-") {
            node = .binary(op, node, try parseTerm())
        }
        return node
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
            guard let variable = Variable(rawValue: name) else {
                throw RegionExpressionError.invalidSyntax(source, reason: "未知变量「\(name)」，可用变量为 s、cw、ch")
            }
            return .variable(variable)
        case .symbol("-"):
            return .negate(try parseFactor())
        case .symbol("("):
            let node = try parseExpression()
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

    private mutating func consumeSymbol(in symbols: String) -> Character? {
        guard index < tokens.count, case .symbol(let symbol) = tokens[index], symbols.contains(symbol) else {
            return nil
        }
        index += 1
        return symbol
    }
}
