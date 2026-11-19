//
//  WindowRow.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI
import ScreenCaptureKit

extension StartupPanel {
    struct WindowRow: View {
        let window: SCWindow
        let isSelected: Bool
        let action: () -> Void
        
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    WindowAppIcon(application: window.owningApplication, size: 28)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(window.displayTitle)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(window.displaySubtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color.blue : Color.primary.opacity(0.12)
                        )
                        .frame(width: 16)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(rowBackground, in: rowShape)
                .overlay {
                    if isSelected {
                        rowShape.strokeBorder(Color.blue.opacity(0.35), lineWidth: 1)
                    }
                }
                .contentShape(rowShape)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
        
        private var rowBackground: Color {
            if isSelected {
                return Color.blue.opacity(0.12)
            }
            if isHovered {
                return Color.primary.opacity(0.055)
            }
            return .clear
        }
        
        private var rowShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        }
    }
}
