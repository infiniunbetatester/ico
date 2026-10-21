import Foundation
import SwiftUI
import AppKit

public enum IslandMode: String, CaseIterable, Identifiable, Sendable {
    case music = "music"
    case files = "files"
    case clipboard = "clipboard"
    case apps = "apps"
    case widgets = "widgets"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .music: return "Музыка"
        case .files: return "Файлы"
        case .clipboard: return "Буфер"
        case .apps: return "Приложения"
        case .widgets: return "Виджеты"
        }
    }
    
    public var iconName: String {
        switch self {
        case .music: return "music.note"
        case .files: return "tray.fill"
        case .clipboard: return "doc.on.clipboard"
        case .apps: return "square.grid.2x2"
        case .widgets: return "puzzlepiece.extension.fill"
        }
    }
    
    public var dimensions: (width: CGFloat, height: CGFloat, radius: CGFloat) {
        switch self {
        case .music: return (640, 340, 30)
        case .files: return (640, 356, 30)
        case .clipboard: return (640, 392, 30)
        case .apps: return (640, 380, 30)
        case .widgets: return (640, 380, 30)
        }
    }
}

public enum IslandView: String, Sendable {
    case compact = "compact"
    case open = "open"
}

public enum CompactStyle: String, CaseIterable, Identifiable, Sendable {
    case standard = "Компактная (24px)"
    case minimal = "Тонкая полоска (6px)"
    case hidden = "Невидимая (0px)"
    
    public var id: String { rawValue }
    
    public var dimensions: (width: CGFloat, height: CGFloat, radius: CGFloat) {
        switch self {
        case .standard: return (180, 24, 12)
        case .minimal: return (120, 6, 3)
        case .hidden: return (0, 0, 0)
        }
    }
}

public struct RealShelfFile: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeFormatted: String
    public let ext: String
}

public struct RealClipItem: Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let date: Date
    public let kind: Kind
    public var isPinned: Bool
    
    public enum Kind: Sendable {
        case text
        case link
        case mail
    }
}

public struct RealAppItem: Identifiable {
    public var id: pid_t { app.processIdentifier }
    public let app: NSRunningApplication
    public var name: String { app.localizedName ?? "Приложение" }
    public var icon: NSImage { app.icon ?? NSWorkspace.shared.icon(for: .application) }
}

@MainActor
@Observable
public final class IslandState {
    public static let shared = IslandState()
    
    // View state
    public var view: IslandView = .compact
    public var mode: IslandMode = .files // User's active tab (persists across open/close)
    public var compactStyle: CompactStyle = .standard
    public var isPinnedOpen: Bool = false
    public var isHoverOpened: Bool = false
    
    // Preferences & Settings
    public var isSettingsOpen: Bool = false {
        didSet {
            updateDimensions()
        }
    }
    
    public var isAlwaysOnTop: Bool = (UserDefaults.standard.object(forKey: "ico_always_on_top") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "ico_always_on_top")
            NotchWindowController.shared.updateWindowLevel(alwaysOnTop: isAlwaysOnTop)
        }
    }
    
    // Dimensions
    public var targetWidth: CGFloat = 180
    public var targetHeight: CGFloat = 24
    public var targetRadius: CGFloat = 12
    
    // Toast
    public var toastMessage: String?
    public var toastIcon: String?
    private var toastTask: Task<Void, Never>?
    
    // MARK: - Media State
    public var isPlaying: Bool = false
    public var trackTitle: String = "Музыка не играет"
    public var trackArtist: String = "Включите YouTube, Telegram, Spotify или любой звук"
    public var elapsed: Double = 0
    public var duration: Double = 180
    public var isFavorite: Bool = false
    public var isShuffle: Bool = false
    public var isRepeat: Bool = false
    public var volume: Double = 65.0
    public var activePlayerApp: String? = nil
    public var visualizerBars: [CGFloat] = [0.2, 0.2, 0.2, 0.2, 0.2]
    public var artworkData: Data? = nil
    public var artworkImage: NSImage? = nil
    public var artworkAuraColor: NSColor? = nil
    
    public var auraSwiftUIColor: Color {
        if let aura = artworkAuraColor {
            return Color(nsColor: aura)
        }
        return Color(red: 0.22, green: 0.82, blue: 0.58)
    }
    
    // MARK: - Files Shelf
    public var shelfFiles: [RealShelfFile] = []
    
    // MARK: - Clipboard History
    public var clipQuery: String = ""
    public var clips: [RealClipItem] = []
    public var copiedClipId: UUID?
    private var lastPasteboardChangeCount: Int = -1
    
    // MARK: - Running Apps
    public var runningApps: [RealAppItem] = []
    public var activeAppIndex: Int = 0
    public var pinnedBundleIds: [String] = ["com.apple.finder", "com.apple.Safari", "com.apple.Terminal"]
    
    private var engineTask: Task<Void, Never>?
    private var visualizerTask: Task<Void, Never>?
    private var isReady: Bool = false
    
    public init() {
        updateDimensions()
        refreshRunningApps()
        startClipboardMonitor()
        startEngine()
        isReady = true
    }
    
    private func notifyTouchBar() {
        guard isReady else { return }
        IslandTouchBarController.shared.refresh(with: self)
    }
    
    public func visibleRect(in bounds: CGRect) -> CGRect {
        if view == .compact && compactStyle == .hidden {
            return .zero
        }
        let w = targetWidth + 36
        let h = targetHeight + (toastMessage != nil ? 65 : 15)
        let x = bounds.midX - (w / 2.0)
        let y = bounds.maxY - h
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    public func setView(_ newView: IslandView) {
        self.view = newView
        updateDimensions()
        notifyTouchBar()
    }
    
    public func setMode(_ newMode: IslandMode) {
        self.mode = newMode
        self.view = .open
        self.isHoverOpened = false
        updateDimensions()
        if newMode == .apps {
            refreshRunningApps()
        }
        notifyTouchBar()
    }
    
    public func setCompactStyle(_ style: CompactStyle) {
        self.compactStyle = style
        if view == .compact {
            updateDimensions()
        }
        showToast("Стиль челки: \(style.rawValue)", icon: "gearshape")
    }
    
    public func togglePin() {
        isPinnedOpen.toggle()
        showToast(isPinnedOpen ? "Остров закреплён" : "Остров откреплён", icon: isPinnedOpen ? "pin.fill" : "pin.slash")
    }
    
    public func collapse() {
        isSettingsOpen = false
        isHoverOpened = false
        setView(.compact)
    }
    
    public func updateDimensions() {
        if view == .compact {
            if compactStyle == .standard && isPlaying {
                targetWidth = 208
                targetHeight = 24
                targetRadius = 12
            } else {
                let d = compactStyle.dimensions
                targetWidth = d.width
                targetHeight = d.height
                targetRadius = d.radius
            }
        } else if isSettingsOpen {
            targetWidth = 640
            targetHeight = 480
            targetRadius = 30
        } else {
            let d = mode.dimensions
            targetWidth = d.width
            targetHeight = d.height
            targetRadius = d.radius
        }
    }
    
    public func showToast(_ text: String, icon: String = "checkmark") {
        toastTask?.cancel()
        toastMessage = text
        toastIcon = icon
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            if !Task.isCancelled {
                self.toastMessage = nil
                self.toastIcon = nil
            }
        }
    }
    
    // MARK: - Files Shelf
    
    public func addRealFile(url: URL) {
        let name = url.lastPathComponent
        var sizeStr = "Файл"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        
        let file = RealShelfFile(
            id: UUID(),
            url: url,
            name: name,
            sizeFormatted: "\(url.pathExtension.uppercased()) · \(sizeStr)",
            ext: url.pathExtension.lowercased()
        )
        shelfFiles.removeAll { $0.url == url }
        shelfFiles.insert(file, at: 0)
        showToast("Добавлено: \(name)", icon: "doc.fill")
        notifyTouchBar()
    }
    
    public func removeShelfFile(id: UUID) {
        shelfFiles.removeAll { $0.id == id }
        notifyTouchBar()
    }
    
    // MARK: - Clipboard Monitor
    
    private func startClipboardMonitor() {
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        if let initial = NSPasteboard.general.string(forType: .string), !initial.isEmpty {
            addClipString(initial)
        }
    }
    
    private func checkClipboardUpdate() {
        let currentCount = NSPasteboard.general.changeCount
        if currentCount != lastPasteboardChangeCount {
            lastPasteboardChangeCount = currentCount
            if let str = NSPasteboard.general.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addClipString(str)
            }
        }
    }
    
    private func addClipString(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clips.first?.text == trimmed { return }
        
        var kind: RealClipItem.Kind = .text
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            kind = .link
        } else if trimmed.contains("@") && !trimmed.contains(" ") {
            kind = .mail
        }
        
        let item = RealClipItem(id: UUID(), text: trimmed, date: Date(), kind: kind, isPinned: false)
        clips.removeAll { $0.text == trimmed }
        clips.insert(item, at: 0)
        if clips.count > 30 { clips.removeLast() }
        notifyTouchBar()
    }
    
    public func copyClipToPasteboard(id: UUID) {
        guard let item = clips.first(where: { $0.id == id }) else { return }
        copiedClipId = id
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        showToast("Скопировано", icon: "doc.on.doc.fill")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self.copiedClipId == id {
                self.copiedClipId = nil
            }
        }
    }
    
    public func removeClip(id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            clips.removeAll { $0.id == id }
        }
        notifyTouchBar()
    }
    
    public func clearAllClips() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            clips.removeAll()
        }
        showToast("Буфер очищен", icon: "trash")
        notifyTouchBar()
    }
    
    // MARK: - Running Apps
    
    public func refreshRunningApps() {
        let currentPid = NSRunningApplication.current.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != currentPid }
        self.runningApps = regularApps.map { RealAppItem(app: $0) }
        if activeAppIndex >= runningApps.count {
            activeAppIndex = max(0, runningApps.count - 1)
        }
    }
    
    public func toggleFavorite() {
        isFavorite.toggle()
    }
    
    public func toggleShuffle() {
        isShuffle.toggle()
    }
    
    public func toggleRepeat() {
        isRepeat.toggle()
    }
    
    public func activateApp(index: Int) {
        guard index >= 0 && index < runningApps.count else { return }
        activeAppIndex = index
        let app = runningApps[index].app
        app.activate()
        showToast("Переход: \(app.localizedName ?? "")", icon: "arrow.up.forward.app")
    }
    
    public func togglePinApp(bundleId: String) {
        if pinnedBundleIds.contains(bundleId) {
            pinnedBundleIds.removeAll { $0 == bundleId }
            showToast("Откреплено", icon: "pin.slash")
        } else {
            pinnedBundleIds.append(bundleId)
            showToast("Закреплено", icon: "pin.fill")
        }
    }
    
    // MARK: - Playback Controls
    
    public func togglePlayPause() {
        self.isPlaying.toggle()
        UniversalMediaController.shared.togglePlayPause()
        notifyTouchBar()
    }
    
    public func nextTrack() {
        UniversalMediaController.shared.nextTrack()
    }
    
    public func previousTrack() {
        UniversalMediaController.shared.previousTrack()
    }
    
    public func seek(to sec: Double) {
        elapsed = sec
    }
    
    public func setVolumeValue(_ val: Double) {
        volume = max(0, min(100, val))
        let scriptVal = Int(val)
        Task.detached(priority: .userInitiated) {
            let script = "set volume output volume \(scriptVal)"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }
    
    // MARK: - Engine Loop
    
    private func startEngine() {
        engineTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { break }
                self.checkClipboardUpdate()
                
                // Real-time second counter for now-playing media
                if self.isPlaying && self.duration > 0 {
                    self.elapsed = min(self.duration, self.elapsed + 1.0)
                }
            }
        }
        
        visualizerTask = Task { @MainActor [weak self] in
            let idleBars: [CGFloat] = [0.15, 0.15, 0.15, 0.15, 0.15]
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self = self else { break }
                if self.isPlaying {
                    withAnimation(.easeInOut(duration: 0.11)) {
                        self.visualizerBars = (0..<5).map { _ in CGFloat.random(in: 0.25...1.0) }
                    }
                } else if self.visualizerBars != idleBars {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.visualizerBars = idleBars
                    }
                }
            }
        }
    }
    
    // MARK: - Direct Media Update
    public func updateNowPlaying(
        title: String,
        artist: String,
        source: String,
        duration: Double,
        elapsed: Double,
        isPlaying: Bool,
        artworkData: Data? = nil
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            self.trackTitle = cleanTitle
            self.trackArtist = artist.isEmpty ? source : artist
            self.activePlayerApp = source
            self.duration = duration > 0 ? duration : 180
            self.elapsed = max(0, elapsed)
            let wasPlaying = self.isPlaying
            self.isPlaying = isPlaying
            
            if wasPlaying != isPlaying && view == .compact {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
                    updateDimensions()
                }
            }
            
            if let data = artworkData, !data.isEmpty {
                if self.artworkData != data {
                    self.artworkData = data
                    if let img = NSImage(data: data) {
                        self.artworkImage = img
                        self.artworkAuraColor = calculateAuraColor(from: img)
                    }
                }
            } else if self.artworkData != nil {
                self.artworkData = nil
                self.artworkImage = nil
                self.artworkAuraColor = nil
            }
            
            notifyTouchBar()
        }
    }
    
    private func calculateAuraColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        let baseColor = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        baseColor.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        let boostedBrightness = max(0.65, min(0.95, br * 1.3))
        let boostedSaturation = max(0.5, min(1.0, s * 1.2))
        return NSColor(calibratedHue: h, saturation: boostedSaturation, brightness: boostedBrightness, alpha: 1.0)
    }
    
    private func syncWithUniversalMedia() {
        // Triggered by engine loop
        UniversalMediaController.shared.refreshNowPlaying()
    }
    
    public var formattedElapsed: String {
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    public var formattedRemaining: String {
        let rem = max(0, duration - elapsed)
        let mins = Int(rem) / 60
        let secs = Int(rem) % 60
        return String(format: "−%d:%02d", mins, secs)
    }
}
