import AppKit
import CoreGraphics
import Foundation

public struct RulerMeasurement: Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let x: CGFloat
    public let y: CGFloat
    public let diagonal: CGFloat
    public let aspectRatio: String
    public let scale: CGFloat
    public let retinaWidth: CGFloat
    public let retinaHeight: CGFloat

    public var dictionary: [String: Any] {
        [
            "width": width,
            "height": height,
            "x": x,
            "y": y,
            "diagonal": diagonal,
            "aspectRatio": aspectRatio,
            "scale": scale,
            "retinaWidth": retinaWidth,
            "retinaHeight": retinaHeight
        ]
    }
}

@MainActor
public final class IslandScreenRuler {
    public static let shared = IslandScreenRuler()

    private var windows: [IslandRulerPanel] = []
    private var continuation: CheckedContinuation<RulerMeasurement?, Never>?
    private var previousApplication: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var sessionID: UUID?

    private init() {}

    public func measure() async -> RulerMeasurement? {
        // If a measurement session is already in progress, cancel previous
        if continuation != nil {
            finish(nil)
        }

        guard !NSScreen.screens.isEmpty else {
            return nil
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<RulerMeasurement?, Never>) in
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
                    self?.finish(nil)
                }
            }

            NSApp.activate(ignoringOtherApps: true)

            for screen in NSScreen.screens {
                let scale = screen.backingScaleFactor
                let panel = IslandRulerPanel(
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

                let rulerView = IslandRulerView(frame: NSRect(origin: .zero, size: screen.frame.size), scale: scale)
                rulerView.onSelected = { [weak self] measurement in
                    self?.finish(measurement)
                }
                rulerView.onCancel = { [weak self] in
                    self?.finish(nil)
                }

                panel.contentView = rulerView
                windows.append(panel)
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(rulerView)
            }

            if windows.isEmpty {
                finish(nil)
            }
        }
    }

    private func finish(_ result: RulerMeasurement?) {
        guard let continuation else { return }
        self.continuation = nil
        sessionID = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        windows.forEach {
            $0.contentView = nil
            $0.orderOut(nil)
            $0.close()
        }
        windows.removeAll()
        if let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
        continuation.resume(returning: result)
    }
}

@MainActor
final class IslandRulerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandRulerView: NSView {
    var onSelected: ((RulerMeasurement) -> Void)?
    var onCancel: (() -> Void)?

    private let scale: CGFloat
    private var start: CGPoint?
    private var current: CGPoint?
    private var isShiftPressed: Bool = false
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, scale: CGFloat) {
        self.scale = scale
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        start = clamped(convert(event.locationInWindow, from: nil))
        current = start
        isShiftPressed = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        isShiftPressed = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start, let current else {
            onCancel?()
            return
        }

        let rect = calculateRect(start: start, current: current, square: isShiftPressed)
        if rect.width >= 2 && rect.height >= 2 {
            let w = round(rect.width)
            let h = round(rect.height)
            let x = round(rect.minX)
            // Convert to macOS top-left screen origin for x/y
            let y = round(bounds.height - rect.maxY)
            let diag = round(sqrt(w * w + h * h) * 10) / 10
            let ratio = formatAspectRatio(w: w, h: h)

            let measurement = RulerMeasurement(
                width: w,
                height: h,
                x: x,
                y: y,
                diagonal: diag,
                aspectRatio: ratio,
                scale: scale,
                retinaWidth: w * scale,
                retinaHeight: h * scale
            )
            onSelected?(measurement)
        } else {
            onCancel?()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        isShiftPressed = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), bounds.width),
            y: min(max(0, point.y), bounds.height)
        )
    }

    private func calculateRect(start: CGPoint, current: CGPoint, square: Bool) -> CGRect {
        var dx = current.x - start.x
        var dy = current.y - start.y

        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx >= 0 ? side : -side
            dy = dy >= 0 ? side : -side
        }

        let x = dx >= 0 ? start.x : start.x + dx
        let y = dy >= 0 ? start.y : start.y + dy
        return CGRect(x: x, y: y, width: abs(dx), height: abs(dy))
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return x
    }

    private func formatAspectRatio(w: CGFloat, h: CGFloat) -> String {
        let iw = Int(w.rounded())
        let ih = Int(h.rounded())
        guard iw > 0, ih > 0 else { return "1:1" }
        let d = gcd(iw, ih)
        let sw = iw / d
        let sh = ih / d
        if sw < 100 && sh < 100 {
            return "\(sw):\(sh)"
        }
        let val = round((w / h) * 100) / 100
        return "\(val):1"
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let activePoint = current ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let isSelecting = (start != nil && current != nil)
        let rect = isSelecting ? calculateRect(start: start!, current: current!, square: isShiftPressed) : nil

        // 1. Dark semi-transparent backdrop with cutout for selection
        let backdropPath = NSBezierPath(rect: bounds)
        if let rect, rect.width > 0, rect.height > 0 {
            backdropPath.append(NSBezierPath(rect: rect))
        }
        backdropPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        backdropPath.fill()

        // 2. Fullscreen crosshair guidelines (cyan / sleek accent)
        ctx.saveGState()
        let guideColor = NSColor.systemCyan.withAlphaComponent(0.45)
        guideColor.setStroke()

        // Horizontal line
        let hLine = NSBezierPath()
        hLine.move(to: NSPoint(x: 0, y: activePoint.y))
        hLine.line(to: NSPoint(x: bounds.width, y: activePoint.y))
        hLine.lineWidth = 1.0
        let dash: [CGFloat] = [4.0, 4.0]
        hLine.setLineDash(dash, count: 2, phase: 0)
        hLine.stroke()

        // Vertical line
        let vLine = NSBezierPath()
        vLine.move(to: NSPoint(x: activePoint.x, y: 0))
        vLine.line(to: NSPoint(x: activePoint.x, y: bounds.height))
        vLine.lineWidth = 1.0
        vLine.setLineDash(dash, count: 2, phase: 0)
        vLine.stroke()
        ctx.restoreGState()

        // 3. Selection outline and measurement details
        if let rect, rect.width >= 2, rect.height >= 2 {
            // Outline
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1.5
            NSColor.cyan.withAlphaComponent(0.95).setStroke()
            outline.stroke()

            // Subtle inner fill
            NSColor.systemCyan.withAlphaComponent(0.08).setFill()
            outline.fill()

            // Badge text calculations
            let w = Int(rect.width.rounded())
            let h = Int(rect.height.rounded())
            let diag = Int(sqrt(rect.width * rect.width + rect.height * rect.height).rounded())
            let ratio = formatAspectRatio(w: rect.width, h: rect.height)

            let mainText = "\(w) × \(h) px"
            let subText = "D: \(diag) px  ·  \(ratio)"

            let fontMain = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .bold)
            let fontSub = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)

            let attrMain: [NSAttributedString.Key: Any] = [
                .font: fontMain,
                .foregroundColor: NSColor.white
            ]
            let attrSub: [NSAttributedString.Key: Any] = [
                .font: fontSub,
                .foregroundColor: NSColor.white.withAlphaComponent(0.7)
            ]

            let sizeMain = (mainText as NSString).size(withAttributes: attrMain)
            let sizeSub = (subText as NSString).size(withAttributes: attrSub)
            let badgeWidth = max(sizeMain.width, sizeSub.width) + 24
            let badgeHeight: CGFloat = 46

            // Position badge near selection (below or above depending on bounds)
            var badgeX = rect.midX - (badgeWidth / 2)
            badgeX = min(max(12, badgeX), bounds.width - badgeWidth - 12)

            var badgeY = rect.minY - badgeHeight - 12
            if badgeY < 20 {
                badgeY = rect.maxY + 12
            }
            if badgeY + badgeHeight > bounds.height - 20 {
                badgeY = rect.midY - (badgeHeight / 2)
            }

            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)

            // Draw pill badge
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10)
            NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.92).setFill()
            badgePath.fill()

            let badgeBorder = NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10)
            badgeBorder.lineWidth = 1
            NSColor.white.withAlphaComponent(0.18).setStroke()
            badgeBorder.stroke()

            // Draw badge text
            (mainText as NSString).draw(
                at: NSPoint(x: badgeRect.midX - (sizeMain.width / 2), y: badgeRect.maxY - sizeMain.height - 7),
                withAttributes: attrMain
            )
            (subText as NSString).draw(
                at: NSPoint(x: badgeRect.midX - (sizeSub.width / 2), y: badgeRect.minY + 6),
                withAttributes: attrSub
            )
        } else {
            // Hint badge when just moving cursor
            let hint = "Нажмите и потяните для замера · ⇧ Квадрат · Esc Отмена" as NSString
            let hintAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
            let hintSize = hint.size(withAttributes: hintAttr)
            let hintW = hintSize.width + 20
            let hintH: CGFloat = 28

            var hx = activePoint.x + 16
            if hx + hintW > bounds.width - 16 {
                hx = activePoint.x - hintW - 16
            }
            var hy = activePoint.y - 36
            if hy < 20 {
                hy = activePoint.y + 16
            }

            let hRect = CGRect(x: hx, y: hy, width: hintW, height: hintH)
            let hPath = NSBezierPath(roundedRect: hRect, xRadius: 7, yRadius: 7)
            NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.88).setFill()
            hPath.fill()
            let hBorder = NSBezierPath(roundedRect: hRect, xRadius: 7, yRadius: 7)
            hBorder.lineWidth = 1
            NSColor.white.withAlphaComponent(0.15).setStroke()
            hBorder.stroke()

            hint.draw(
                at: NSPoint(x: hRect.midX - (hintSize.width / 2), y: hRect.midY - (hintSize.height / 2)),
                withAttributes: hintAttr
            )
        }
    }
}
