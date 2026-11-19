//
//  WindowAppIcon.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import SwiftUI
import ScreenCaptureKit

extension StartupPanel {
    struct WindowAppIcon: View {
        let application: SCRunningApplication?
        var size: CGFloat = 28
        
        var body: some View {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: size, height: size)
                        .background(
                            Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        )
                }
            }
            .frame(width: size, height: size)
        }
        
        private var icon: NSImage? {
            guard let application,
                  let running = NSRunningApplication(processIdentifier: application.processID)
            else { return nil }

            return running.icon
        }
    }
}
