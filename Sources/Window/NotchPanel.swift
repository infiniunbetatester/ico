import AppKit
import SwiftUI

public final class NotchPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .mainMenu + 1
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.acceptsMouseMovedEvents = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowKeyChange),
            name: NSWindow.didBecomeKeyNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowKeyChange),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }
    
    @objc private func handleWindowKeyChange() {
        DispatchQueue.main.async {
            if IslandState.shared.view == .open {
                IslandTouchBarController.shared.updateTouchBarPresentation(isOpen: true)
            }
        }
    }
    
    
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
    
    public override func makeTouchBar() -> NSTouchBar? {
        return IslandTouchBarController.shared.touchBar
    }
}

/// Custom container view that passes mouse events through to underlying macOS windows
/// whenever the cursor is outside the island's visible bounds.
public final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    public override func hitTest(_ point: NSPoint) -> NSView? {
        // Calculate the hit area of the island inside this view's bounds
        let state = IslandState.shared
        let islandW = state.targetWidth + 36 // include shoulder flare and margin
        let islandH = max(26, state.targetHeight + (state.toastMessage != nil ? 65 : 15))
        
        let minX = (self.bounds.width - islandW) / 2.0
        let minY = self.bounds.height - islandH
        let islandRect = NSRect(x: minX, y: minY, width: islandW, height: islandH)
        
        if islandRect.contains(point) {
            return super.hitTest(point)
        }
        
        // Pass clicks straight through to desktop and underlying applications
        return nil
    }
}
