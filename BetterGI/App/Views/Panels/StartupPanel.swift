//
//  StartupPanel.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import SwiftUI
import ScreenCaptureKit

struct StartupPanel: View {
    let viewModel: SharedViewModel
    let session: StartupViewModel
    
    private var selectedWindow: SCWindow? {
        viewModel.selectedWindow
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择录制窗口")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("选择一个窗口作为操作目标；切换窗口会自动停止当前录制。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Label("\(viewModel.avaliableWindows.count) 个窗口", systemImage: "macwindow.on.rectangle")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                    Button {
                        Task { await refreshWindows() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.055), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("刷新窗口列表")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 4)
            
            GeometryReader { proxy in
                content(isWide: proxy.size.width >= 620)
            }
        }
        .background { PanelGradientBackground() }
        .onAppear {
            guard viewModel.avaliableWindows.isEmpty else { return }
            Task { await refreshWindows() }
        }
        .onChange(of: viewModel.selectedWindowID) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if oldValue != nil {
                session.handleSelectionChange()
            }
            
            if let newValue,
               let window = viewModel.avaliableWindows.first(where: { $0.windowID == newValue }) {
                session.log("已选择窗口：\(window.displayTitle)", level: .info)
            } else if oldValue != nil {
                session.log("已取消窗口选择", level: .warning)
            }
        }
    }
    
    @ViewBuilder
    private func content(isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 16) {
                windowListCard()
                    .frame(width: 296)
                VStack(spacing: 14) {
                    operationCard
                    logCard
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 20)
        } else {
            VStack(spacing: 14) {
                windowListCard()
                    .frame(height: 150)
                operationCard
                logCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }
    
    private var logCard: some View {
        StartupLogView(logs: session.logs, onClear: session.clearLogs)
    }
    
    private func windowListCard() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("桌面窗口")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
                .opacity(0.6)
            if viewModel.avaliableWindows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 20, weight: .light))
                    
                    Text("没有可录制的窗口")
                        .font(.system(size: 11.5, weight: .medium))
                    
                    Text("请确认屏幕录制权限后刷新窗口列表")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(viewModel.avaliableWindows, id: \.windowID) { window in
                            WindowRow(
                                window: window,
                                isSelected: window.windowID == viewModel.selectedWindowID
                            ) {
                                select(window)
                            }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { PanelCardBackground() }
    }
    
    private var operationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("操作")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                statusBadge
            }
            selectedSummary
            HStack(spacing: 8) {
                startButton
                stopButton
            }
            Divider()
                .opacity(0.6)
            ProcessingMetricsView(session: session)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PanelCardBackground() }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if session.isBusy {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("处理中")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        } else if session.isRecording {
            badge("录制中", color: .red)
        } else if selectedWindow != nil {
            badge("已就绪", color: .blue)
        } else {
            badge("未选择窗口", color: .secondary)
        }
    }
    
    private func badge(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            
            Text(text)
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
    }
    
    @ViewBuilder
    private var selectedSummary: some View {
        if let window = selectedWindow {
            HStack(spacing: 9) {
                WindowAppIcon(application: window.owningApplication, size: 30)
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(window.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(window.displaySubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        } else {
            HStack(spacing: 9) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("尚未选择窗口")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("从窗口列表中选择一个操作目标")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            }
        }
    }
    
    private var canStartRecording: Bool {
        selectedWindow != nil && !session.isRecording && !session.isBusy
    }
    
    private var canStopRecording: Bool {
        session.isRecording && !session.isBusy
    }
    
    private var startButton: some View {
        Button {
            guard let window = selectedWindow, canStartRecording else { return }
            Task { await session.startRecording(window: window) }
        } label: {
            Label("开始录制", systemImage: "record.circle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(canStartRecording ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    canStartRecording ? AppPalette.blue : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(canStartRecording ? 0.14 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canStartRecording)
        .help("开始录制所选窗口")
    }
    
    private var stopButton: some View {
        Button {
            session.stopRecording(trigger: .user)
        } label: {
            Label("停止录制", systemImage: "stop.circle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(canStopRecording ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Color.red.opacity(canStopRecording ? 0.14 : 0.05),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            Color.red.opacity(canStopRecording ? 0.32 : 0.10),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!canStopRecording)
        .help("停止当前录制")
    }
    
    private func select(_ window: SCWindow) {
        guard viewModel.selectedWindowID != window.windowID else { return }
        
        withAnimation(.snappy(duration: 0.22)) {
            viewModel.selectedWindowID = window.windowID
        }
    }
    
    private func refreshWindows() async {
        await viewModel.getOrRefreshAvailableContents()
        
        if viewModel.avaliableWindows.isEmpty {
            session.log("未发现可用窗口，请检查屏幕录制权限", level: .warning)
        } else {
            session.log("窗口列表已刷新：\(viewModel.avaliableWindows.count) 个窗口", level: .info)
        }
        
        // 刷新后如果选中的窗口已经不存在，就回到未选择状态，避免继续把它当作操作目标。
        if let selection = viewModel.selectedWindowID,
           !viewModel.avaliableWindows.contains(where: { $0.windowID == selection }) {
            viewModel.selectedWindowID = nil
        }
    }
}

