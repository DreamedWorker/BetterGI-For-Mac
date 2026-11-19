//
//  LiquidGlassButton.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    /// 按钮的着色，nil 表示跟随系统强调色。
    var tint: Color?
    /// 是否使用强调样式（实心着色玻璃），用于页面里的主要操作。
    var isProminent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                content
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                content
                    .buttonStyle(.glass)
                    .tint(tint)
            }
        } else {
            content
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background {
                    if isProminent {
                        shape.fill(tint ?? Color.accentColor)
                    } else {
                        shape.fill(.ultraThinMaterial)
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
}

extension View {
    /// 应用液态玻璃按钮样式，自动回退到旧系统
    /// - Parameters:
    ///   - cornerRadius: 回退方案使用的圆角半径
    ///   - tint: 按钮着色，nil 表示跟随系统强调色
    ///   - prominent: 是否使用强调（实心着色）样式
    func liquidGlassButton(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        prominent: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                isProminent: prominent
            )
        )
    }
}
