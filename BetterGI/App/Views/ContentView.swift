//
//  ContentView.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import SwiftUI

struct ContentView: View {
    @State private var isShowingWelcome = AppPreferences.isAppFirstOpen
    
    private let brandBlue = Color(red: 0.22, green: 0.49, blue: 0.98)
    private let brandTeal = Color(red: 0.12, green: 0.74, blue: 0.76)
    
    var body: some View {
        if AppPreferences.isAppFirstOpen {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        brandBlue.opacity(0.05),
                        brandTeal.opacity(0.035)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    AppIconView(size: 112)
                    
                    VStack(spacing: 6) {
                        Text("BetterGI For Mac")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("基于计算机视觉技术，让Mac上的原神体验更好。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            isShowingWelcome = true
                        } label: {
                            Label("打开引导窗口", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $isShowingWelcome) {
                WelcomeView(
                    onFinish: { relaunchApp() },
                    onRestart: { relaunchApp() }
                )
            }
        } else {
            MainStageView()
        }
    }
    
    private func relaunchApp() {
        isShowingWelcome = false
        
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                // 新实例启动失败时不能退出，否则 App 会直接消失。
                if let error {
                    showRelaunchError(error)
                    return
                }
                
                NSApplication.shared.terminateClosingSheets()
            }
        }
    }
    
    private func showRelaunchError(_ error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法重新启动 BetterGI"
        alert.informativeText = "\(error.localizedDescription)\n请手动退出并重新打开 App。"
        alert.runModal()
    }
}
