//
//  LogEntry.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Foundation

struct LogEntry: Identifiable {
    enum Level {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let date: Date
    let level: Level
    let message: String
}
