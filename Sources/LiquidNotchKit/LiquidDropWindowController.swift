import AppKit
import SwiftUI

/// One stable physical window, one AppKit dragging destination.
/// Normal clicks outside visible content pass through via ignoresMouseEvents.
@MainActor public final class LiquidDropWindowController: NSWindowController, NSWindowDelegate {
    public let session: LiquidDropSession
    public var isExternalDragActive: Bool { session.isExternalDragActive }
    private let configuration: LiquidDropConfiguration
    private let host: LiquidDropHostView
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var displayObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var screenID: NSNumber?
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastIdleChangeCount: Int
    private var wasButtonDown = false
    private var downPoint = CGPoint.zero
    private var sawDragMotion = false
    private var suppressUntilMouseUp = false
    private var releasedAt: TimeInterval?
    private var lastPhysicsTime = ProcessInfo.processInfo.systemUptime
    private var emittedActive = false

    public init<Content: View>(screen: NSScreen, configuration: LiquidDropConfiguration,
                              @ViewBuilder content: () -> Content) {
        self.configuration = configuration
        let session = LiquidDropSession()
        self.session = session
        let surface = LiquidDropSurface(session: session, configuration: configuration, normal: AnyView(content()))
        host = LiquidDropHostView(session: session, configuration: configuration, content: AnyView(surface))
        lastIdleChangeCount = NSPasteboard(name: .drag).changeCount
        screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let size = configuration.receiverSize
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = LiquidNotchPanel(contentRect: frame)
        super.init(window: panel)
        panel.contentView = host
        panel.dragDestination = host.destination
        panel.delegate = self
        host.destination.onEntered = { [weak self] in self?.nativeEntered() }
        host.destination.onExited = { [weak self] in self?.session.clearDwell() }
        host.destination.onEnded = { [weak self] accepted in self?.nativeEnded(accepted: accepted) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(screen:configuration:content:)") }

    public override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
        window?.layoutIfNeeded()
        logNotchLayout()
        startMonitoring()
    }

    public override func close() {
        stopMonitoring()
        super.close()
    }

    public func windowWillClose(_ notification: Notification) { stopMonitoring() }

    private func startMonitoring() {
        guard timer == nil else { return }
        lastIdleChangeCount = dragPasteboard.changeCount
        lastPhysicsTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.observeMouse(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.observeMouse(event) }
            return event
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.repositionAfterDisplayChange() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.repositionAfterDisplayChange() } }
        poll()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        globalMonitor = nil
        localMonitor = nil
        displayObserver = nil
        spaceObserver = nil
        finishActivity(accepted: false)
        host.destination.resetNativeState()
        host.routesExternalDrag = false
        window?.ignoresMouseEvents = true
    }

    private func observeMouse(_ event: NSEvent) {
        if event.type == .leftMouseDown && !wasButtonDown {
            downPoint = NSEvent.mouseLocation
            sawDragMotion = false
        }
        poll()
    }

    @objc private func poll() {
        guard let window, window.isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let screenPoint = NSEvent.mouseLocation
        let point = host.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let buttonDown = (NSEvent.pressedMouseButtons & 1) != 0
        let inField = configuration.captureContains(point, in: host.bounds)
        let hasFiles = LiquidFilePayload.advertisesFiles(dragPasteboard)
        let actualNative = host.destination.nativeInside

        if buttonDown {
            if !wasButtonDown {
                downPoint = screenPoint
                releasedAt = nil
            }
            if hypot(screenPoint.x - downPoint.x, screenPoint.y - downPoint.y) >= 8 { sawDragMotion = true }
            let freshDragBoard = dragPasteboard.changeCount != lastIdleChangeCount
            let fileCandidate = inField && ((freshDragBoard && sawDragMotion && hasFiles) || actualNative)
            if !suppressUntilMouseUp && configuration.canAcceptDrops() && fileCandidate {
                beginActivity()
                host.routesExternalDrag = true
                setIgnoresMouse(false)
                session.track(point, bounds: host.bounds, configuration: configuration)
            } else if !inField || !configuration.canAcceptDrops() {
                finishActivity(accepted: false)
                host.routesExternalDrag = false
                host.destination.resetNativeState()
                routeOrdinaryMouse(at: point)
            } else if !session.isExternalDragActive {
                routeOrdinaryMouse(at: point)
            }
        } else {
            if wasButtonDown { releasedAt = now }
            lastIdleChangeCount = dragPasteboard.changeCount
            sawDragMotion = false
            suppressUntilMouseUp = false
            let awaitingNativeDrop = host.destination.nativeSequence != nil && session.isExternalDragActive
                && now - (releasedAt ?? now) < 0.18
            if !awaitingNativeDrop {
                finishActivity(accepted: false)
                host.routesExternalDrag = false
                host.destination.resetNativeState()
                routeOrdinaryMouse(at: point)
            }
        }
        wasButtonDown = buttonDown

        if session.phase != .idle, now - lastPhysicsTime >= 1.0 / 120 {
            let dt = now - lastPhysicsTime
            lastPhysicsTime = now
            session.advance(dt: dt, now: now, bounds: host.bounds,
                            nativeDragInside: host.destination.nativeInside,
                            buttonDown: buttonDown, configuration: configuration)
        } else if session.phase == .idle { lastPhysicsTime = now }
    }

    private func routeOrdinaryMouse(at point: CGPoint) {
        let metrics = configuration.currentMetrics()
        setIgnoresMouse(!metrics.isVisible || !metrics.interactiveRect(in: host.bounds).contains(point))
    }

    private func setIgnoresMouse(_ ignores: Bool) {
        if window?.ignoresMouseEvents != ignores { window?.ignoresMouseEvents = ignores }
    }

    private func beginActivity() {
        guard !session.isExternalDragActive else { return }
        session.begin(metrics: configuration.currentMetrics(), expanded: configuration.isExpanded())
        emittedActive = true
        configuration.activityChanged(true)
        configuration.log("file drag armed; physical receiver=\(configuration.receiverSize)")
    }

    private func finishActivity(accepted: Bool) {
        session.finish(accepted: accepted, now: ProcessInfo.processInfo.systemUptime)
        if emittedActive {
            emittedActive = false
            configuration.activityChanged(false)
        }
    }

    private func nativeEntered() {
        guard !suppressUntilMouseUp else { return }
        beginActivity()
        host.routesExternalDrag = true
        setIgnoresMouse(false)
    }

    private func nativeEnded(accepted: Bool) {
        finishActivity(accepted: accepted)
        suppressUntilMouseUp = true
        host.routesExternalDrag = false
    }

    public func logNotchLayout() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let windowGap = screen.frame.maxY - window.frame.maxY
        let hosting = host.hosting
        let contentTopInWindow = hosting.convert(
            NSPoint(x: hosting.bounds.midX,
                    y: hosting.isFlipped ? hosting.bounds.minY : hosting.bounds.maxY),
            to: nil
        )
        let contentTopOnScreen = window.convertPoint(toScreen: contentTopInWindow)
        print("NOTCH_LAYOUT", "screen=", screen.frame,
              "window=", window.frame, "windowTopGap=", windowGap,
              "hostingFrame=", hosting.frame, "hostingBounds=", hosting.bounds,
              "hostingSafeArea=", hosting.safeAreaInsets,
              "contentTopGap=", screen.frame.maxY - contentTopOnScreen.y)
    }

    private func repositionAfterDisplayChange() {
        let selected = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == screenID
        } ?? NSScreen.main
        guard let selected, let window else { return }
        finishActivity(accepted: false)
        host.destination.resetNativeState()
        host.routesExternalDrag = false
        let size = configuration.receiverSize
        let rect = CGRect(x: selected.frame.midX - size.width / 2,
                          y: selected.frame.maxY - size.height,
                          width: size.width, height: size.height)
        window.setFrame(rect, display: true, animate: false)
        host.frame = CGRect(origin: .zero, size: rect.size)
        host.hosting.frame = CGRect(origin: .zero, size: rect.size)
        host.destination.frame = CGRect(origin: .zero, size: rect.size)
        window.layoutIfNeeded()
        logNotchLayout()
    }
}

@MainActor final class LiquidNotchPanel: NSPanel {
    weak var dragDestination: LiquidDropDestinationView?
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        // The WINDOW is the sole registered endpoint. SwiftUI subviews cannot hide it
        // once their competing onDrop/dropDestination handlers are removed.
        registerForDraggedTypes(LiquidFilePayload.acceptedTypes)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    func wantsPeriodicDraggingUpdates() -> Bool { true }
    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragDestination?.draggingEntered(sender) ?? []
    }
    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragDestination?.draggingUpdated(sender) ?? []
    }
    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dragDestination?.draggingExited(sender)
    }
    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dragDestination?.prepareForDragOperation(sender) ?? false
    }
    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dragDestination?.performDragOperation(sender) ?? false
    }
    func draggingEnded(_ sender: any NSDraggingInfo) {
        dragDestination?.draggingEnded(sender)
    }
}
