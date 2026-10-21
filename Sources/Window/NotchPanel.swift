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
        let islandW = max(state.targetWidth + 36, isCompact ? 240 : 0)
        let islandH = max(26, state.targetHeight + (state.toastMessage != nil ? 65 : 15))
        
        let minX = (self.bounds.width - islandW) / 2.0
        let minY = self.bounds.height - max(islandH, isCompact ? 36 : 0)
        let islandRect = NSRect(x: minX, y: minY, width: islandW, height: max(islandH, isCompact ? 36 : 0))
        
        if islandRect.contains(point) {
            return super.hitTest(point)
        }
        
        // Pass clicks straight through to desktop and underlying applications
        return nil
    }
    
    // MARK: - Drag & Drop directly onto Notch
    
    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let state = IslandState.shared
        withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
            IslandTools.shared.leaveTools()
            state.isSettingsOpen = false
            state.setMode(.files)
            state.isHoverOpened = true
            state.setView(.open)
        }
        return .copy
    }
    
    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }
        
        let state = IslandState.shared
        for url in urls {
            state.addRealFile(url: url)
        }
        NSSound(named: "Glass")?.play()
        state.showToast("Файл добавлен на полку 📥", icon: "tray.and.arrow.down.fill")
        return true
    }
}
