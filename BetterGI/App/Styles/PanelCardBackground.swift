//
//  PanelCardBackground.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI

struct PanelCardBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        
        shape
            .fill(Color.primary.opacity(0.035))
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}
