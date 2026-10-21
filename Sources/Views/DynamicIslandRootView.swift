import SwiftUI

public struct DynamicIslandRootView: View {
    @State private var state = IslandState.shared
    @State private var tools = IslandTools.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var leaveTask: Task<Void, Never>?
    @State private var isDragTargeted: Bool = false
    
    public init() {}
    
    public var body: some View {
        let currentWidth = state.targetWidth
        let currentHeight = state.targetHeight
        let currentRadius = state.targetRadius
        let shoulderFlare: CGFloat = (state.view == .compact && state.compactStyle == .minimal) ? 6 : 16
        let totalShapeWidth = currentWidth + (shoulderFlare * 2)
        let isHiddenCompact = (state.view == .compact && state.compactStyle == .hidden)
        
        VStack(spacing: 0) {
            if !isHiddenCompact {
                ZStack(alignment: .top) {
                    // Frosted Glass Silhouette (Ultra-thin material with deep dark tint)
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        
                        Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.82)
                    }
                    .frame(width: totalShapeWidth, height: currentHeight, alignment: .top)
                    .clipShape(
                        NotchSurfaceShape(
                            cornerRadius: currentRadius,
                            shoulderWidth: shoulderFlare,
                            shoulderHeight: 14
                        )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 14)
                    .shadow(color: Color.black.opacity(0.2), radius: 32, x: 0, y: 24)
                    
                    // Content Layer
                    VStack(spacing: 0) {
                        if state.view == .open {
                            // Header Bar (Pin, Tabs, Compact Settings, Collapse)
                            HeaderTabBar(state: state)
                                .padding(.top, 38)
                            
                            // Active Content Panel (Settings, Tools or standard tabs)
                            ZStack(alignment: .top) {
                                if state.isSettingsOpen {
                                    SettingsPanel(state: state)
                                        .transition(
                                            .opacity.combined(
                                                with: .scale(scale: 0.97, anchor: .top)
                                            )
                                        )
                                } else if tools.active != nil {
                                    IslandToolsPanel(tools: tools)
                                        .transition(
                                            .opacity.combined(
                                                with: .scale(scale: 0.97, anchor: .top)
                                            )
                                        )
                                } else {
                                    Group {
                                        switch state.mode {
                                        case .music:
                                            MusicPanel(state: state)
                                        case .files:
                                            FilesPanel(state: state)
                                        case .clipboard:
                                            ClipboardPanel(state: state)
                                        case .apps:
                                            AppsPanel(state: state)
                                        case .widgets:
                                            WidgetsPanel(state: state)
                                        }
                                    }
                                    .transition(
                                        .opacity.combined(
                                            with: .scale(scale: 0.97, anchor: .top)
                                        )
                                    )
                                }
                            }
                            .animation(IslandToolsStyle.spring, value: tools.active)
                            .animation(IslandToolsStyle.spring, value: state.isSettingsOpen)
                            .padding(.top, 14)
                            .frame(width: currentWidth, alignment: .top)
                        } else {
                            // Compact Notch state
                            CompactView(state: state) {
                                withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
                                    state.setView(.open)
                                }
                            }
                            .frame(height: currentHeight)
                        }
                    }
                    .frame(width: currentWidth, height: currentHeight, alignment: .top)
                    
                    // Toast notification pill below island
                    if let msg = state.toastMessage {
                        Button {
                            if UpdateChecker.shared.hasAvailableUpdate {
                                UpdateChecker.shared.openDownloadPage()
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: state.toastIcon ?? "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.66, green: 0.8, blue: 0.73))
                                
                                Text(msg)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(Color(red: 0.85, green: 0.85, blue: 0.89))
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(
                                ZStack {
                                    Rectangle().fill(.ultraThinMaterial)
                                    Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.9)
                                }
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .offset(y: currentHeight + 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(width: totalShapeWidth, height: currentHeight, alignment: .top)
                .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                    handleDrop(providers)
                }
                .onChange(of: isDragTargeted) { _, targeted in
                    if targeted {
                        withAnimation(IslandToolsStyle.spring) {
                            tools.leaveTools()
                            state.isSettingsOpen = false
                            state.setMode(.files)
                            state.isHoverOpened = true
                            state.setView(.open)
                        }
                    }
                }
                .animation(.spring(response: 0.44, dampingFraction: 0.88), value: currentWidth)
                .animation(.spring(response: 0.44, dampingFraction: 0.88), value: currentHeight)
                .animation(.spring(response: 0.44, dampingFraction: 0.88), value: currentRadius)
                .onChange(of: state.view) { _, newView in
                    WidgetManager.shared.notifyWidgets(isExpanded: newView == .open)
                }
                .onHover { hovering in
                    handleHover(hovering)
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            tools.attach(to: state)
        }
    }
    
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        leaveTask?.cancel()
        
        if hovering {
            if state.view == .compact && state.compactStyle != .hidden {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 170_000_000)
                    if !Task.isCancelled && state.view == .compact {
                        state.isHoverOpened = true
                        withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
                            state.setView(.open)
                        }
                    }
                }
            }
        } else {
            if state.isHoverOpened && !state.isPinnedOpen {
                leaveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    if !Task.isCancelled && !state.isPinnedOpen && state.isHoverOpened && !tools.ocr.isSelecting {
                        state.isHoverOpened = false
                        withAnimation(IslandToolsStyle.spring) {
                            state.setView(.compact)
                        }
                    }
                }
            }
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didLoad = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                Task { @MainActor in
                    state.addRealFile(url: url)
                    NSSound(named: "Glass")?.play()
                }
            }
            didLoad = true
        }
        return didLoad
    }
}
