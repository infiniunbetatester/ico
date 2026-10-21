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
        self.registerForDraggedTypes([.fileURL, .URL])
        
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
/// whenever the cursor is outside the island's visible bounds, and accepts dragged files to drop directly onto the shelf.
public final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    public required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .URL])
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL])
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let state = IslandState.shared
        let isCompact = (state.view == .compact)
        let dropletExtra = (state.isDropletPulling && isCompact) ? state.dropletExtraHeight : 0
        let islandW = max(state.targetWidth + 36 + (dropletExtra * 0.4), isCompact ? 240 : 0)
        let islandH = max(26, state.targetHeight + dropletExtra + (state.toastMessage != nil ? 65 : 15))
        
        let minX = (self.bounds.width - islandW) / 2.0
        let minY = self.bounds.height - max(islandH, isCompact ? 36 : 0)
        let islandRect = NSRect(x: minX, y: minY, width: islandW, height: max(islandH, isCompact ? 36 : 0))
        
        if islandRect.contains(point) {
            return super.hitTest(point)
        }
        
        // Intercept drags approaching the gravity field when mouse button is held down
        let dx = abs(point.x - (self.bounds.width / 2.0))
        let dy = self.bounds.height - point.y
        if NSEvent.pressedMouseButtons != 0 && dx <= 280.0 && dy >= 0 && dy <= 400.0 {
            return self
        }
        
        // Pass clicks straight through to desktop and underlying applications
        return nil
    }
    
    // MARK: - Drag & Drop directly onto Notch / Droplet Shelf
    
    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return handleDragTracking(sender)
    }
    
    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return handleDragTracking(sender)
    }
    
    private func handleDragTracking(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let state = IslandState.shared
        if state.view == .open {
            return .copy
        }
        
        let loc = sender.draggingLocation
        let midX = self.bounds.width / 2.0
        let topY = self.bounds.height
        let dx = abs(loc.x - midX)
        let dy = max(0, topY - loc.y) // Distance in points from screen top down to cursor
        
        // Gravitational reach: within 280pt horizontally and 380pt vertically below the notch
        let maxReachX: CGFloat = 280.0
        let maxReachY: CGFloat = 380.0
        
        if dx <= maxReachX && dy <= maxReachY {
            // As cursor moves down, stretch the liquid droplet down towards the cursor!
            let extraHeight = min(105.0, max(24.0, (dy - 8.0) * 0.72))
            let isTargeted = (dy <= (24.0 + extraHeight + 35.0)) && (dx <= 120.0)
            
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                state.setDropletPull(extraHeight: extraHeight, isTargeted: isTargeted)
            }
            return .copy
        } else {
            // Outside gravity reach
            if state.isDropletPulling {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    state.resetDropletPull()
                }
            }
            return .copy
        }
    }
    
    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        let state = IslandState.shared
        if state.view == .compact && state.isDropletPulling {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                state.resetDropletPull()
            }
        }
    }
    
    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            let state = IslandState.shared
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                state.resetDropletPull()
            }
            return false
        }
        
        let state = IslandState.shared
        if state.view == .compact {
            state.absorbDroppedFiles(urls: urls)
            return true
        } else {
            for url in urls {
                state.addRealFile(url: url)
            }
            NSSound(named: "Glass")?.play()
            state.showToast("Файл добавлен на полку 📥", icon: "tray.and.arrow.down.fill")
            return true
        }
    }
}
