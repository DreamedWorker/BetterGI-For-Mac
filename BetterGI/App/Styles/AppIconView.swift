//
//  AppIconView.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

struct AppIconView: View {
    var size: CGFloat = 80

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
