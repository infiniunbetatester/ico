import AppKit
import SwiftUI

@MainActor
public final class NotchWindowController {
    public static let shared = NotchWindowController()
    
    private var fileDropWindow: LiquidDropWindowController?
    public var isVisible: Bool = true
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    
    public init() {}
    
    public func setup() {
        guard let screen = targetScreen() ?? NSScreen.main else { return }
        
        fileDropWindow?.close()
        fileDropWindow = makeICOFileDropWindow(
            screen: screen,
            welcomeIsVisible: { ICOFirstLaunch.isRequired }
        )
        fileDropWindow?.showWindow(nil)
        
        if let window = fileDropWindow?.window {
            window.level = IslandState.shared.isAlwaysOnTop ? (.mainMenu + 1) : .normal
        }
        recenterOnCurrentScreen()
        
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
                guard !ICOFirstLaunch.isRequired else { return event }
                guard !state.isExternalFileDragActive else { return event }
                state.collapse()
                return nil
            }
            
            return event
        }
        
        // Auto-collapse when user clicks outside the island on desktop or other apps
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                guard !ICOFirstLaunch.isRequired else { return }
                guard !IslandState.shared.isExternalFileDragActive else { return }
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
                guard !IslandState.shared.isExternalFileDragActive else { return }
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
        guard let window = fileDropWindow?.window else { return }
        if isVisible {
            window.orderOut(nil)
            isVisible = false
        } else {
            window.orderFrontRegardless()
            isVisible = true
        }
    }
    
    public func recenterOnCurrentScreen() {
        guard let window = fileDropWindow?.window, let screen = targetScreen() else { return }
        let size = window.frame.size
        let newFrame = CGRect(
            x: screen.frame.midX - (size.width / 2.0),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(newFrame, display: true)
    }
    
    private func targetScreen() -> NSScreen? {
        if let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        let mousePoint = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mousePoint, $0.frame, false) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
    
    public func updateWindowLevel(alwaysOnTop: Bool) {
        guard let window = fileDropWindow?.window else { return }
        window.level = alwaysOnTop ? (.mainMenu + 1) : .normal
        if alwaysOnTop {
            window.orderFrontRegardless()
        }
    }
}
