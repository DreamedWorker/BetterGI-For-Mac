//
//  PanelGradientBackground.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

/// 品牌配色
enum AppPalette {
    static let blue = Color(red: 0.22, green: 0.49, blue: 0.98)
    static let teal = Color(red: 0.12, green: 0.74, blue: 0.76)
}

/// 侧边栏各功能页面共用的背景渐变。
struct PanelGradientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                AppPalette.blue.opacity(0.05),
                AppPalette.teal.opacity(0.035)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
