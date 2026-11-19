//
//  BetterGIDelegate.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import AppKit
import Foundation

final class BetterGIDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
        
        if !AppPermission.allGrantedBySystem {
            AppPreferences.isAppFirstOpen = true
        }
    }
    
    @objc private func handleQuitAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        NSApplication.shared.terminateClosingSheets()
    }
}

extension NSApplication {
    func terminateClosingSheets() {
        for window in windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
        }

        DispatchQueue.main.async {
            self.terminate(nil)
        }
    }
}
