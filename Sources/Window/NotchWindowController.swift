import AppKit
import SwiftUI

@MainActor
public final class NotchWindowController {
    public static let shared = NotchWindowController()
    
    private var panel: NotchPanel?
    private let fixedCanvasSize: CGSize = CGSize(width: 860, height: 520)
    public var isVisible: Bool = true
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    
    public init() {}
    
    public func setup() {
        guard let screen = NSScreen.main else { return }
        
        let initialRect = calculateStationaryFrame(on: screen)
        let panel = NotchPanel(contentRect: initialRect)
        
        let rootView = DynamicIslandRootView()
        let hostingView = PassThroughHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        
        panel.contentView = hostingView
        panel.setFrame(initialRect, display: true)
        panel.level = IslandState.shared.isAlwaysOnTop ? (.mainMenu + 1) : .normal
        panel.orderFrontRegardless()
        
        self.panel = panel
        
        // Listen for screen resolution and Space (fullscreen) changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recenterOnCurrentScreen()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recenterOnCurrentScreen()
            }
        }
        
        setupKeyAndClickMonitors()
    }
    
    private func setupKeyAndClickMonitors() {
        // Keyboard Shortcuts: Esc to collapse
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let state = IslandState.shared
            
            if event.keyCode == 53 { // Escape
                state.collapse()
                return nil
            }
            
            return event
        }
        
        // Auto-collapse when user clicks outside the island on desktop or other apps
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                let state = IslandState.shared
                if state.view == .open && !state.isPinnedOpen {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
                        state.collapse()
                    }
                }
            }
        }
        
        // Auto-collapse when user switches to any other application (clicks window, dock, or Cmd+Tab)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let state = IslandState.shared
                if state.view == .open && !state.isPinnedOpen {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
                        state.collapse()
                    }
                }
            }
        }
    }
    
    public func toggleVisibility() {
        guard let panel = panel else { return }
        if isVisible {
            panel.orderOut(nil)
            isVisible = false
        } else {
            panel.orderFrontRegardless()
            isVisible = true
        }
    }
    
    public func recenterOnCurrentScreen() {
        guard let panel = panel, let screen = targetScreen() else { return }
        let newFrame = calculateStationaryFrame(on: screen)
        panel.setFrame(newFrame, display: true)
    }
    
    private func targetScreen() -> NSScreen? {
        // If there's a screen with a built-in hardware notch (MacBook Pro), prioritize it
        if let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        
        // Next, check which screen currently hosts the mouse cursor
        let mousePoint = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mousePoint, $0.frame, false) }) {
            return mouseScreen
        }
        
        return NSScreen.main ?? NSScreen.screens.first
    }
    
    private func calculateStationaryFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - (fixedCanvasSize.width / 2.0)
        let y = screenFrame.maxY - fixedCanvasSize.height
        return NSRect(x: x, y: y, width: fixedCanvasSize.width, height: fixedCanvasSize.height)
    }
    
    public func updateWindowLevel(alwaysOnTop: Bool) {
        guard let panel else { return }
        panel.level = alwaysOnTop ? (.mainMenu + 1) : .normal
        if alwaysOnTop {
            panel.orderFrontRegardless()
        }
    }
}
