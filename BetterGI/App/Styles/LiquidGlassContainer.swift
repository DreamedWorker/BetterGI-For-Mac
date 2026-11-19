//
//  LiquidGlassContainer.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

/// 玻璃的两种变体。
///
/// - `regular`：系统默认的自适应玻璃，磨砂感强、模糊重，适合压在内容简单的背景上。
/// - `clear`：更透明、模糊更轻，背景的细节和边缘折射会明显得多。
enum LiquidGlassStyle {
    case regular
    case clear
}

struct LiquidGlassContainer : ViewModifier {
    var cornerRadius: CGFloat
    /// 玻璃的着色。为 nil 时使用系统的默认（无色）玻璃。
    var tint: Color?
    /// 玻璃变体。
    var style: LiquidGlassStyle
    /// 是否让玻璃响应指针交互（悬停时轻微放大 / 高光）。
    var isInteractive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
        } else {
            // 回退：有色玻璃用「材质 + 着色叠加」近似，无色玻璃保持原来的 ultraThinMaterial。
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if let tint {
                                shape.fill(tint.opacity(0.35))
                            }
                        }
                }
                .overlay(
                    shape
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass: Glass = style == .clear ? .clear : .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
}

extension View {
    /// 应用液态玻璃容器样式，自动回退到旧系统
    /// - Parameters:
    ///   - cornerRadius: 容器圆角半径
    ///   - tint: 玻璃着色，nil 表示使用系统默认的无色玻璃
    ///   - style: 玻璃变体
    ///   - interactive: 是否启用玻璃的指针交互反馈
    func liquidGlassContainer(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        style: LiquidGlassStyle = .regular,
        interactive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassContainer(
                cornerRadius: cornerRadius,
                tint: tint,
                style: style,
                isInteractive: interactive
            )
        )
    }
}
