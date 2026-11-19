//
//  BetterGIApp.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import SwiftUI

@main
struct BetterGIApp: App {
    @NSApplicationDelegateAdaptor(BetterGIDelegate.self) private var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
    }
}
