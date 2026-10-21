import AppKit
import SwiftUI

extension NSTouchBarItem.Identifier {
    static let islandTabs = NSTouchBarItem.Identifier("com.ico.app.touchbar.tabs")
    static let islandContext = NSTouchBarItem.Identifier("com.ico.app.touchbar.context")
    static let islandToggle = NSTouchBarItem.Identifier("com.ico.app.touchbar.toggle")
    static let islandPin = NSTouchBarItem.Identifier("com.ico.app.touchbar.pin")
    static let islandControlStrip = NSTouchBarItem.Identifier("com.ico.app.controlStrip")
}

@MainActor
public final class IslandTouchBarController: NSObject, NSTouchBarDelegate {
    public static let shared = IslandTouchBarController()
    
    public var touchBar: NSTouchBar?
    private var controlStripItem: NSCustomTouchBarItem?
    private var segmentedControl: NSSegmentedControl?
    private var contextStackView: NSStackView?
    private var toggleButton: NSButton?
    private var pinButton: NSButton?
    private var isSystemModalActive: Bool = false
    private weak var musicPlayButton: NSButton?
    private weak var musicTrackButton: NSButton?
    
    private typealias DFRElementSetControlStripPresenceFunc = @convention(c) (CFString, Bool) -> Void
    
    public override init() {
        super.init()
    }
    
    public func setup() {
        setupControlStripItem()
        buildMainTouchBar()
        if IslandState.shared.isTouchBarPersistent {
            updateTouchBarPresentation(isOpen: false)
        }
    }
    
    // MARK: - System Control Strip Item
    
    private func setupControlStripItem() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW),
              let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            return
        }
        
        let setPresence = unsafeBitCast(sym, to: DFRElementSetControlStripPresenceFunc.self)
        let identifier = NSTouchBarItem.Identifier.islandControlStrip
        
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "Dynamic Notch") ?? NSImage(),
            target: self,
            action: #selector(toggleIslandFromTouchBar)
        )
        button.bezelStyle = .rounded
        item.view = button
        self.controlStripItem = item
        
        let sel = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: sel) {
            _ = NSTouchBarItem.perform(sel, with: item)
            setPresence(identifier.rawValue as CFString, true)
        }
    }
    
    @objc private func toggleIslandFromTouchBar() {
        let state = IslandState.shared
        withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
            if state.view == .open {
                state.collapse()
            } else {
                state.setView(.open)
            }
        }
        updateToggleIcon(state: state)
        updateTouchBarPresentation(isOpen: state.view == .open)
    }
    
    // MARK: - Main Touch Bar
    
    public func buildMainTouchBar() {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [
            .islandToggle,
            .islandPin,
            .islandTabs,
            .islandContext
        ]
        self.touchBar = bar
    }
    
    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let state = IslandState.shared
        
        switch identifier {
        case .islandToggle:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = makeTouchBarButton(
                title: "",
                systemImage: state.view == .open ? "chevron.up" : "macwindow.badge.plus",
                minWidth: 36,
                maxWidth: 42,
                action: #selector(toggleIslandFromTouchBar)
            )
            item.view = button
            self.toggleButton = button
            return item
            
        case .islandPin:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = makeTouchBarButton(
                title: "",
                systemImage: state.isPinnedOpen ? "pin.fill" : "pin",
                minWidth: 36,
                maxWidth: 42,
                action: #selector(togglePinFromTouchBar)
            )
            if state.isPinnedOpen {
                button.bezelColor = NSColor.systemBlue.withAlphaComponent(0.45)
            }
            item.view = button
            self.pinButton = button
            return item
            
        case .islandTabs:
            let item = NSCustomTouchBarItem(identifier: identifier)
            
            // Apple HIG: Use crisp icons for Touch Bar tabs to keep it compact and leave maximum space for context buttons
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let musicImg = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Музыка")?.withSymbolConfiguration(config) ?? NSImage()
            let filesImg = NSImage(systemSymbolName: "tray.fill", accessibilityDescription: "Файлы")?.withSymbolConfiguration(config) ?? NSImage()
            let clipImg = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Буфер")?.withSymbolConfiguration(config) ?? NSImage()
            let appsImg = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Окна")?.withSymbolConfiguration(config) ?? NSImage()
            let widgetImg = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: "Виджеты")?.withSymbolConfiguration(config) ?? NSImage()
            
            let segmented = NSSegmentedControl(
                images: [musicImg, filesImg, clipImg, appsImg, widgetImg],
                trackingMode: .selectOne,
                target: self,
                action: #selector(tabSegmentChanged(_:))
            )
            segmented.segmentStyle = .separated
            segmented.selectedSegment = activeSegmentIndex(for: state.mode)
            item.view = segmented
            self.segmentedControl = segmented
            return item
            
        case .islandContext:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 6
            stack.alignment = .centerY
            item.view = stack
            self.contextStackView = stack
            
            rebuildContextViews(state: state)
            return item
            
        default:
            return nil
        }
    }
    
    private func activeSegmentIndex(for mode: IslandMode) -> Int {
        switch mode {
        case .music: return 0
        case .files: return 1
        case .clipboard: return 2
        case .apps: return 3
        case .widgets: return 4
        }
    }
    
    @objc private func tabSegmentChanged(_ sender: NSSegmentedControl) {
        IslandTools.shared.leaveTools()
        let state = IslandState.shared
        let shouldOpen = state.expandOnTouchBarTap || (state.view == .open)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            switch sender.selectedSegment {
            case 0: state.setMode(.music, openIsland: shouldOpen)
            case 1: state.setMode(.files, openIsland: shouldOpen)
            case 2: state.setMode(.clipboard, openIsland: shouldOpen)
            case 3: state.setMode(.apps, openIsland: shouldOpen)
            case 4: state.setMode(.widgets, openIsland: shouldOpen)
            default: break
            }
        }
        rebuildContextViews(state: state)
    }
    
    @objc private func togglePinFromTouchBar() {
        let state = IslandState.shared
        state.togglePin()
        updatePinButton(state: state)
    }
    
    private func updatePinButton(state: IslandState) {
        let iconName = state.isPinnedOpen ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        pinButton?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Pin")?.withSymbolConfiguration(config)
        pinButton?.bezelColor = state.isPinnedOpen ? NSColor.systemBlue.withAlphaComponent(0.45) : nil
    }
    
    // MARK: - Dynamic Live Context Refresh & Modal Priority
    
    public func refresh(with passedState: IslandState? = nil) {
        let state = passedState ?? IslandState.shared
        if let segmented = segmentedControl {
            segmented.selectedSegment = activeSegmentIndex(for: state.mode)
        }
        updateToggleIcon(state: state)
        updatePinButton(state: state)
        rebuildContextViews(state: state)
        
        // Ensure Touch Bar has top system priority whenever the island is open
        updateTouchBarPresentation(isOpen: state.view == .open)
    }
    
    public func updateTouchBarPresentation(isOpen: Bool) {
        guard let bar = self.touchBar else { return }
        let identifier = NSTouchBarItem.Identifier.islandControlStrip.rawValue
        let selPresentPlacement = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let selPresent = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        let selDismiss = NSSelectorFromString("dismissSystemModalTouchBar:")
        
        let state = IslandState.shared
        let shouldBeActive = state.isTouchBarPersistent || isOpen
        
        if shouldBeActive {
            guard !isSystemModalActive else { return }
            
            if NSTouchBar.responds(to: selPresentPlacement) {
                typealias PresentPlacementFunc = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, String) -> Void
                let imp = unsafeBitCast(NSTouchBar.method(for: selPresentPlacement), to: PresentPlacementFunc.self)
                imp(NSTouchBar.self, selPresentPlacement, bar, 1, identifier)
                isSystemModalActive = true
            } else if NSTouchBar.responds(to: selPresent) {
                typealias PresentFunc = @convention(c) (AnyClass, Selector, NSTouchBar, String) -> Void
                let imp = unsafeBitCast(NSTouchBar.method(for: selPresent), to: PresentFunc.self)
                imp(NSTouchBar.self, selPresent, bar, identifier)
                isSystemModalActive = true
            }
        } else {
            guard isSystemModalActive else { return }
            if NSTouchBar.responds(to: selDismiss) {
                typealias DismissFunc = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
                let imp = unsafeBitCast(NSTouchBar.method(for: selDismiss), to: DismissFunc.self)
                imp(NSTouchBar.self, selDismiss, bar)
                isSystemModalActive = false
            }
        }
    }
    
    private func updateToggleIcon(state: IslandState) {
        let iconName = state.view == .open ? "chevron.up" : "macwindow.badge.plus"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        toggleButton?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Toggle")?.withSymbolConfiguration(config)
    }
    
    private func rebuildContextViews(state: IslandState) {
        guard let stack = contextStackView else { return }
        
        // If already in music mode and buttons are present, update in-place with smooth color animation!
        if state.mode == .music,
           let playBtn = musicPlayButton,
           let trackBtn = musicTrackButton,
           playBtn.superview == stack,
           trackBtn.superview == stack {
            updateMusicButtonsInPlace(playBtn: playBtn, trackBtn: trackBtn, state: state)
            return
        }
        
        musicPlayButton = nil
        musicTrackButton = nil
        
        // Remove all previous subviews
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        switch state.mode {
        case .clipboard:
            buildClipboardButtons(into: stack, state: state)
            
        case .files:
            buildFilesButtons(into: stack, state: state)
            
        case .apps:
            buildAppsButtons(into: stack, state: state)
            
        case .music:
            buildMusicButtons(into: stack, state: state)
            
        case .widgets:
            buildWidgetsButtons(into: stack, state: state)
        }
        
        stack.layoutSubtreeIfNeeded()
    }
    
    private func buildWidgetsButtons(into stack: NSStackView, state: IslandState) {
        let manager = WidgetManager.shared
        for widget in manager.installedWidgets.prefix(3) {
            let isCurrent = manager.activeWidgetId == widget.id
            let btn = makeTouchBarButton(
                title: widget.name,
                systemImage: widget.iconName,
                action: #selector(widgetButtonTapped(_:))
            )
            btn.identifier = NSUserInterfaceItemIdentifier(widget.id)
            if isCurrent {
                btn.bezelColor = NSColor.systemBlue.withAlphaComponent(0.4)
            }
            stack.addArrangedSubview(btn)
        }
    }
    
    @objc private func widgetButtonTapped(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue {
            WidgetManager.shared.activeWidgetId = id
            rebuildContextViews(state: IslandState.shared)
        }
    }
    
    // MARK: - Native Touch Bar Button Factory (Apple HIG Spec)
    
    private func makeRoundedThumbnail(from image: NSImage, size: NSSize = NSSize(width: 20, height: 20), cornerRadius: CGFloat = 4.5) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }
    
    private func makeTouchBarButton(
        title: String,
        systemImage: String? = nil,
        customImage: NSImage? = nil,
        minWidth: CGFloat = 36,
        maxWidth: CGFloat? = nil,
        tag: Int = 0,
        auraColor: NSColor? = nil,
        action: Selector?
    ) -> NSButton {
        let btn: NSButton
        if let action = action {
            btn = NSButton(title: title, target: self, action: action)
        } else {
            btn = NSButton(title: title, target: nil, action: nil)
        }
        
        btn.bezelStyle = .rounded
        btn.setButtonType(.momentaryPushIn)
        btn.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        btn.tag = tag
        btn.lineBreakMode = .byTruncatingTail
        
        if let cell = btn.cell as? NSButtonCell {
            cell.lineBreakMode = .byTruncatingTail
            cell.truncatesLastVisibleLine = true
        }
        
        if let systemImage = systemImage {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            if let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                btn.image = img
                btn.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            }
        } else if let customImage = customImage {
            btn.image = customImage
            btn.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        
        if let aura = auraColor {
            btn.bezelColor = aura.withAlphaComponent(0.4)
        }
        
        btn.imageScaling = .scaleProportionallyDown
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 30).isActive = true
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
        if let maxWidth = maxWidth {
            btn.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true
        }
        
        btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        btn.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return btn
    }
    
    // MARK: - Clipboard Touch Bar Buttons
    
    private func buildClipboardButtons(into stack: NSStackView, state: IslandState) {
        if state.clips.isEmpty {
            let emptyBtn = makeTouchBarButton(title: "Буфер пуст", systemImage: "doc.on.clipboard", minWidth: 100, action: nil)
            emptyBtn.isEnabled = false
            stack.addArrangedSubview(emptyBtn)
        } else {
            for (index, clip) in state.clips.prefix(3).enumerated() {
                let cleanText = clip.text.replacingOccurrences(of: "\n", with: " ")
                let truncated = cleanText.count > 16 ? String(cleanText.prefix(15)) + "…" : cleanText
                let iconName: String
                switch clip.kind {
                case .link: iconName = "link"
                case .mail: iconName = "envelope.fill"
                case .text: iconName = "doc.on.doc"
                }
                let btn = makeTouchBarButton(
                    title: truncated,
                    systemImage: iconName,
                    minWidth: 60,
                    maxWidth: 130,
                    tag: index,
                    action: #selector(clipTapped(_:))
                )
                stack.addArrangedSubview(btn)
            }
        }
    }
    
    @objc private func clipTapped(_ sender: NSButton) {
        let state = IslandState.shared
        let index = sender.tag
        if index >= 0 && index < state.clips.count {
            let clip = state.clips[index]
            state.copyClipToPasteboard(id: clip.id)
        }
    }
    
    // MARK: - Files Touch Bar Buttons
    
    private func buildFilesButtons(into stack: NSStackView, state: IslandState) {
        if state.shelfFiles.isEmpty {
            let emptyBtn = makeTouchBarButton(
                title: "Добавить файл",
                systemImage: "plus",
                minWidth: 120,
                action: #selector(addFileTapped)
            )
            stack.addArrangedSubview(emptyBtn)
        } else {
            for (index, file) in state.shelfFiles.prefix(3).enumerated() {
                let truncated = file.name.count > 14 ? String(file.name.prefix(13)) + "…" : file.name
                let icon = NSWorkspace.shared.icon(forFile: file.url.path)
                let btn = makeTouchBarButton(
                    title: truncated,
                    customImage: icon,
                    minWidth: 60,
                    maxWidth: 120,
                    tag: index,
                    action: #selector(fileTapped(_:))
                )
                stack.addArrangedSubview(btn)
            }
            
            let addBtn = makeTouchBarButton(
                title: "",
                systemImage: "plus",
                minWidth: 36,
                maxWidth: 40,
                action: #selector(addFileTapped)
            )
            stack.addArrangedSubview(addBtn)
        }
    }
    
    @objc private func fileTapped(_ sender: NSButton) {
        let state = IslandState.shared
        let index = sender.tag
        if index >= 0 && index < state.shelfFiles.count {
            let file = state.shelfFiles[index]
            NSWorkspace.shared.open(file.url)
        }
    }
    
    @objc private func addFileTapped() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                IslandState.shared.addRealFile(url: url)
            }
        }
    }
    
    // MARK: - Running Apps Touch Bar Buttons
    
    private func buildAppsButtons(into stack: NSStackView, state: IslandState) {
        for (index, appItem) in state.runningApps.prefix(4).enumerated() {
            let truncated = appItem.name.count > 12 ? String(appItem.name.prefix(11)) + "…" : appItem.name
            let btn = makeTouchBarButton(
                title: truncated,
                customImage: appItem.icon,
                minWidth: 50,
                maxWidth: 105,
                tag: index,
                action: #selector(appTapped(_:))
            )
            stack.addArrangedSubview(btn)
        }
    }
    
    @objc private func appTapped(_ sender: NSButton) {
        let state = IslandState.shared
        let index = sender.tag
        if index >= 0 && index < state.runningApps.count {
            state.activateApp(index: index)
        }
    }
    
    // MARK: - Music Touch Bar Buttons (Transport + Title)
    
    private func buildMusicButtons(into stack: NSStackView, state: IslandState) {
        let prevBtn = makeTouchBarButton(
            title: "",
            systemImage: "backward.fill",
            minWidth: 36,
            maxWidth: 42,
            action: #selector(musicPrevTapped)
        )
        stack.addArrangedSubview(prevBtn)
        
        let playBtn = makeTouchBarButton(
            title: "",
            systemImage: state.isPlaying ? "pause.fill" : "play.fill",
            minWidth: 36,
            maxWidth: 42,
            auraColor: state.isPlaying ? state.artworkAuraColor?.withAlphaComponent(0.4) : nil,
            action: #selector(musicPlayTapped)
        )
        stack.addArrangedSubview(playBtn)
        
        let nextBtn = makeTouchBarButton(
            title: "",
            systemImage: "forward.fill",
            minWidth: 36,
            maxWidth: 42,
            action: #selector(musicNextTapped)
        )
        stack.addArrangedSubview(nextBtn)
        
        let fullTitle = state.trackArtist.isEmpty ? state.trackTitle : "\(state.trackTitle) – \(state.trackArtist)"
        let cleanTitle = fullTitle.replacingOccurrences(of: "\n", with: " ")
        let truncated = cleanTitle.count > 24 ? String(cleanTitle.prefix(23)) + "…" : cleanTitle
        
        let artworkThumb: NSImage?
        if let art = state.artworkImage {
            artworkThumb = makeRoundedThumbnail(from: art, size: NSSize(width: 20, height: 20), cornerRadius: 4.5)
        } else {
            artworkThumb = nil
        }
        
        let trackBtn = makeTouchBarButton(
            title: truncated,
            systemImage: artworkThumb == nil ? "music.note" : nil,
            customImage: artworkThumb,
            minWidth: 80,
            maxWidth: 220,
            auraColor: state.isPlaying ? state.artworkAuraColor : nil,
            action: #selector(musicTitleTapped)
        )
        stack.addArrangedSubview(trackBtn)
        
        self.musicPlayButton = playBtn
        self.musicTrackButton = trackBtn
    }
    
    private func updateMusicButtonsInPlace(playBtn: NSButton, trackBtn: NSButton, state: IslandState) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let iconName = state.isPlaying ? "pause.fill" : "play.fill"
        playBtn.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        
        let fullTitle = state.trackArtist.isEmpty ? state.trackTitle : "\(state.trackTitle) – \(state.trackArtist)"
        let cleanTitle = fullTitle.replacingOccurrences(of: "\n", with: " ")
        let truncated = cleanTitle.count > 24 ? String(cleanTitle.prefix(23)) + "…" : cleanTitle
        trackBtn.title = truncated
        
        let artworkThumb: NSImage?
        if let art = state.artworkImage {
            artworkThumb = makeRoundedThumbnail(from: art, size: NSSize(width: 20, height: 20), cornerRadius: 4.5)
        } else {
            artworkThumb = nil
        }
        trackBtn.image = artworkThumb ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        
        let targetPlayAura = state.isPlaying ? state.artworkAuraColor?.withAlphaComponent(0.4) : nil
        let targetTrackAura = state.isPlaying ? state.artworkAuraColor : nil
        
        // Smoothly animate bezelColor transition on Touch Bar without flickering or rebuilding!
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.55
            context.allowsImplicitAnimation = true
            playBtn.animator().bezelColor = targetPlayAura
            trackBtn.animator().bezelColor = targetTrackAura
        }
    }
    
    @objc private func musicPrevTapped() {
        IslandState.shared.previousTrack()
    }
    
    @objc private func musicPlayTapped() {
        IslandState.shared.togglePlayPause()
    }
    
    @objc private func musicNextTapped() {
        IslandState.shared.nextTrack()
    }
    
    @objc private func musicTitleTapped() {
        let state = IslandState.shared
        let shouldOpen = state.expandOnTouchBarTap || (state.view == .open)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            state.setMode(.music, openIsland: shouldOpen)
        }
    }
}
