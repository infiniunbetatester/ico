import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit
import Vision
import Observation

private struct IslandOCRFrame: @unchecked Sendable {
    let image: CGImage
}

private enum IslandTextError: LocalizedError {
    case permission
    case missingDisplay
    case noText
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permission: "Разрешите приложению запись экрана в настройках конфиденциальности."
        case .missingDisplay: "Экран отключён. Повторите выделение."
        case .noText: "В выбранной области текст не найден."
        case .unavailable: "Не удалось начать выделение области."
        }
    }
}

@MainActor
@Observable
public final class IslandScreenText {
    public var text = ""
    public private(set) var isBusy = false
    public private(set) var isSelecting = false
    public private(set) var didCopy = false
    public private(set) var error: String?

    @ObservationIgnored var onCompleted: (() -> Void)?
    @ObservationIgnored private let picker = IslandRegionPicker()
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?

    public init() {}

    public func capture() {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        didCopy = false

        Task { @MainActor in
            defer {
                isBusy = false
                isSelecting = false
            }

            do {
                if !CGPreflightScreenCaptureAccess() {
                    guard CGRequestScreenCaptureAccess() else {
                        throw IslandTextError.permission
                    }
                }

                isSelecting = true
                let region = try await picker.select()
                isSelecting = false

                // Let WindowServer remove the selection windows.
                try await Task.sleep(nanoseconds: 90_000_000)

                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )

                guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
                    throw IslandTextError.missingDisplay
                }

                // Exclude every window belonging to this utility, including the island itself.
                let ownApplications = content.applications.filter {
                    $0.processID == ProcessInfo.processInfo.processIdentifier
                }

                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: ownApplications,
                    exceptingWindows: []
                )

                let configuration = SCStreamConfiguration()
                configuration.sourceRect = region.sourceRect
                configuration.width = max(1, Int((region.sourceRect.width * region.scale).rounded()))
                configuration.height = max(1, Int((region.sourceRect.height * region.scale).rounded()))
                configuration.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )

                let frame = IslandOCRFrame(image: image)

                let recognized = try await Task.detached(priority: .userInitiated) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true

                    let supported = try request.supportedRecognitionLanguages()
                    let preferred = ["ru-RU", "en-US"].filter { supported.contains($0) }
                    if !preferred.isEmpty {
                        request.recognitionLanguages = preferred
                    }

                    let handler = VNImageRequestHandler(cgImage: frame.image, options: [:])
                    try handler.perform([request])

                    let observations = request.results ?? []
                    return observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }.value

                guard !recognized.isEmpty else {
                    throw IslandTextError.noText
                }

                text = recognized
                copy()
                onCompleted?()
            } catch is CancellationError {
                // Keep the previous result and clipboard intact.
            } catch {
                self.error = error.localizedDescription
                onCompleted?()
            }
        }
    }

    public func copy() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            error = "Не удалось записать текст в буфер обмена."
            return
        }
        didCopy = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.didCopy = false
        }
    }

    public func openPermissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class IslandRegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class IslandRegionPicker {
    struct Region {
        let displayID: CGDirectDisplayID
        let sourceRect: CGRect
        let scale: CGFloat
    }

    private var windows: [IslandRegionPanel] = []
    private var continuation: CheckedContinuation<Region, Error>?
    private var previousApplication: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var sessionID: UUID?

    func select() async throws -> Region {
        guard continuation == nil, !NSScreen.screens.isEmpty else {
            throw IslandTextError.unavailable
        }

        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Region, Error>) in
                self.continuation = continuation
                self.previousApplication = NSWorkspace.shared.frontmostApplication
                let session = UUID()
                self.sessionID = session

                self.screenObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard self?.sessionID == session else { return }
                        self?.finish(.failure(CancellationError()))
                    }
                }

                NSApp.activate(ignoringOtherApps: true)

                for screen in NSScreen.screens {
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                        continue
                    }
                    let displayID = CGDirectDisplayID(number.uint32Value)
                    let height = screen.frame.height
                    let scale = screen.backingScaleFactor

                    let panel = IslandRegionPanel(
                        contentRect: screen.frame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    panel.level = .screenSaver
                    panel.isOpaque = false
                    panel.backgroundColor = .clear
                    panel.hasShadow = false
                    panel.isReleasedWhenClosed = false
                    panel.hidesOnDeactivate = false
                    panel.collectionBehavior = [
                        .canJoinAllSpaces,
                        .fullScreenAuxiliary,
                        .stationary
                    ]

                    let view = IslandRegionView(frame: NSRect(origin: .zero, size: screen.frame.size))
                    view.onSelected = { [weak self] rect in
                        let sourceRect = CGRect(
                            x: rect.minX,
                            y: height - rect.maxY,
                            width: rect.width,
                            height: rect.height
                        )
                        self?.finish(.success(
                            Region(displayID: displayID, sourceRect: sourceRect, scale: scale)
                        ))
                    }
                    view.onCancel = { [weak self] in
                        self?.finish(.failure(CancellationError()))
                    }

                    panel.contentView = view
                    windows.append(panel)
                    panel.makeKeyAndOrderFront(nil)
                    panel.makeFirstResponder(view)
                }

                if windows.isEmpty {
                    finish(.failure(IslandTextError.unavailable))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<Region, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        sessionID = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class IslandRegionView: NSView {
    var onSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var start: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = clamped(convert(event.locationInWindow, from: nil))
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        selection = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if let selection, selection.width >= 4, selection.height >= 4 {
            onSelected?(selection)
        } else {
            start = nil
            selection = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
        }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.32).setFill()
        dim.fill()

        if let selection {
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.95).setStroke()
            outline.stroke()

            let size = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let textSize = size.size(withAttributes: attributes)
            let label = CGRect(
                x: min(
                    max(12, selection.midX - textSize.width / 2 - 9),
                    bounds.width - textSize.width - 30
                ),
                y: max(12, selection.minY - 31),
                width: textSize.width + 18,
                height: 23
            )
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: label, xRadius: 8, yRadius: 8).fill()
            size.draw(at: CGPoint(x: label.minX + 9, y: label.minY + 5), withAttributes: attributes)
        }

        let hint = "Выделите область · Esc — отмена" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = hint.size(withAttributes: attributes)
        let pill = CGRect(
            x: bounds.midX - size.width / 2 - 17,
            y: 38,
            width: size.width + 34,
            height: 34
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 17, yRadius: 17).fill()
        hint.draw(at: CGPoint(x: pill.minX + 17, y: pill.minY + 10), withAttributes: attributes)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
