//
//  MainStageView.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import SwiftUI

struct MainStageView: View {
    @State private var selectedFeature: AppFeature = .main
    
    @State private var windows = SharedViewModel()
    @State private var session = StartupViewModel()
    
    @ViewBuilder
    var body: some View {
        NavigationSplitView(
            sidebar: {
                List(selection: $selectedFeature) {
                    ForEach(AppFeature.allCases) { feature in
                        Label(feature.title, systemImage: feature.systemImage)
                            .tag(feature)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 250)
            },
            detail: {
                switch selectedFeature {
                case .main:
                    StartupPanel(viewModel: windows, session: session)
                case .realtimeTasks:
                    RealtimeTasksPanel(session: session, onOpenStartup: { selectedFeature = .main })
                }
            }
        )
        .navigationTitle(selectedFeature.title)
        .onDisappear {
            session.handleDisappearance()
        }
    }
}

private enum AppFeature: String, CaseIterable, Identifiable {
    case main
    case realtimeTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main:
            return "启动"
        case .realtimeTasks:
            return "实时任务"
        }
    }

    var systemImage: String {
        switch self {
        case .main:
            return "play"
        case .realtimeTasks:
            return "bolt"
        }
    }
}
