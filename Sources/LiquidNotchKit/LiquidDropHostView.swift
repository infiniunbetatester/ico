import AppKit
import SwiftUI
import QuartzCore

@MainActor final class LiquidDropHostView: NSView {
    let destination: LiquidDropDestinationView
    let hosting: NSHostingView<AnyView>
    let configuration: LiquidDropConfiguration
    let session: LiquidDropSession
    var routesExternalDrag = false {
        didSet { destination.routesExternalDrag = routesExternalDrag }
    }
    override var isFlipped: Bool { true }

    init(session: LiquidDropSession, configuration: LiquidDropConfiguration, content: AnyView) {
        self.session = session
        self.configuration = configuration
        destination = LiquidDropDestinationView(session: session, configuration: configuration)
        let root = content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .all)
        let hostingView = NSHostingView(rootView: AnyView(root))
        if #available(macOS 14.0, *) {
            hostingView.safeAreaRegions = []
        }
        hostingView.sizingOptions = []
        self.hosting = hostingView
        super.init(frame: CGRect(origin: .zero, size: configuration.receiverSize))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        destination.autoresizingMask = [.width, .height]
        destination.frame = bounds
        addSubview(hosting)
        addSubview(destination)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(session:configuration:content:)") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // hitTest receives a point in the SUPERVIEW's coordinates.
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if routesExternalDrag && configuration.captureContains(local, in: bounds) { return destination }
        let metrics = configuration.currentMetrics()
        guard metrics.isVisible, metrics.interactiveRect(in: bounds).contains(local) else { return nil }
        // hosting's superview is self: passing local here is intentional.
        return hosting.hitTest(local)
    }
}

@MainActor final class LiquidDropDestinationView: NSView {
    let session: LiquidDropSession
    let configuration: LiquidDropConfiguration
    let fileReceiver = LiquidFileReceiver()
    var nativeInside = false
    var routesExternalDrag = false {
        didSet {
            guard oldValue != routesExternalDrag else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = routesExternalDrag
                ? NSColor.black.withAlphaComponent(configuration.receiverPaintAlpha).cgColor
                : NSColor.clear.cgColor
            CATransaction.commit()
        }
    }
    var nativeSequence: Int?
    var onEntered: (() -> Void)?
    var onExited: (() -> Void)?
    var onEnded: ((Bool) -> Void)?
    private var prepared: (sequence: Int, payload: LiquidFilePayload)?
    private var lastCommittedSequence: Int?
    override var isFlipped: Bool { true }

    init(session: LiquidDropSession, configuration: LiquidDropConfiguration) {
        self.session = session
        self.configuration = configuration
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes(LiquidFilePayload.acceptedTypes)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(session:configuration:)") }

    private func trace(_ stage: String, _ sender: any NSDraggingInfo) {
        let local = convert(sender.draggingLocation, from: nil)
        let screenPoint = window?.convertPoint(toScreen: sender.draggingLocation)
        let fileReadable = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let promisesReadable = sender.draggingPasteboard.canReadObject(
            forClasses: [NSFilePromiseReceiver.self], options: nil)
        print("NATIVE_DROP", stage,
              "seq=", sender.draggingSequenceNumber,
              "window=", window?.frame as Any,
              "ignored=", window?.ignoresMouseEvents as Any,
              "bounds=", bounds, "local=", local,
              "screenPoint=", screenPoint as Any,
              "mask=", sender.draggingSourceOperationMask.rawValue,
              "file=", fileReadable, "promises=", promisesReadable,
              "types=", sender.draggingPasteboard.types as Any)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return routesExternalDrag && configuration.captureContains(local, in: bounds) ? self : nil
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        trace("ENTER", sender)
        let isEligible = eligible(sender)
        configuration.log("ENTER eligible=\(isEligible)")
        guard isEligible else { return [] }
        if nativeSequence != sender.draggingSequenceNumber {
            prepared = nil
            session.clearDwell()
        }
        nativeInside = true
        nativeSequence = sender.draggingSequenceNumber
        onEntered?()
        configuration.log("native draggingEntered; sequence=\(sender.draggingSequenceNumber)")
        return update(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        trace("UPDATE", sender)
        let isEligible = eligible(sender)
        guard isEligible else {
            configuration.log("UPDATE not eligible")
            nativeInside = false
            session.clearDwell()
            return []
        }
        if nativeSequence != sender.draggingSequenceNumber || !nativeInside { return draggingEntered(sender) }
        let op = update(sender)
        let point = convert(sender.draggingLocation, from: nil)
        let accepts = session.accepts(point, in: bounds, configuration: configuration)
        configuration.log("UPDATE op=\(op.rawValue) accepts=\(accepts) point=\(point)")
        return op
    }

    private func eligible(_ sender: any NSDraggingInfo) -> Bool {
        configuration.canAcceptDrops()
            && sender.draggingSourceOperationMask.contains(.copy)
            && LiquidFilePayload.advertisesFiles(sender.draggingPasteboard)
            && lastCommittedSequence != sender.draggingSequenceNumber
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // NSDraggingInfo uses destination WINDOW coordinates. Convert to our flipped view.
        let point = convert(sender.draggingLocation, from: nil)
        session.track(point, bounds: bounds, configuration: configuration)
        return session.accepts(point, in: bounds, configuration: configuration) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        trace("PREPARE", sender)
        guard eligible(sender), nativeInside, nativeSequence == sender.draggingSequenceNumber else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        guard session.accepts(point, in: bounds, configuration: configuration),
              let payload = LiquidFilePayload.read(sender.draggingPasteboard) else {
            prepared = nil
            configuration.log("prepare rejected: outside visible target or no file payload")
            return false
        }
        prepared = (sender.draggingSequenceNumber, payload)
        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        trace("PERFORM", sender)
        guard eligible(sender), nativeInside,
              let prepared, prepared.sequence == sender.draggingSequenceNumber,
              session.accepts(convert(sender.draggingLocation, from: nil), in: bounds, configuration: configuration) else {
            return false
        }
        // Mark before callbacks; reentrant or duplicate perform calls cannot import twice.
        lastCommittedSequence = sender.draggingSequenceNumber
        self.prepared = nil
        let accepted = fileReceiver.receive(prepared.payload, configuration: configuration)
        nativeInside = false
        session.finish(accepted: accepted, now: ProcessInfo.processInfo.systemUptime)
        configuration.log(accepted ? "native drop accepted" : "native drop failed")
        onEnded?(accepted)
        return accepted
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        nativeInside = false
        prepared = nil
        session.clearDwell()
        configuration.log("native draggingExited")
        onExited?()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        let accepted = lastCommittedSequence == sender.draggingSequenceNumber
        nativeInside = false
        nativeSequence = nil
        prepared = nil
        session.finish(accepted: accepted, now: ProcessInfo.processInfo.systemUptime)
        onEnded?(accepted)
    }

    func resetNativeState() {
        nativeInside = false
        nativeSequence = nil
        prepared = nil
        session.clearDwell()
    }
}
