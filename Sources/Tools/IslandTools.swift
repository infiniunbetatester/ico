import SwiftUI
import AppKit
import Observation

public enum IslandTool: String, CaseIterable, Identifiable {
    case text
    case qr
    case timer
    case mixer

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .text: "Текст"
        case .qr: "QR-код"
        case .timer: "Таймер"
        case .mixer: "Микшер"
        }
    }
    public var icon: String {
        switch self {
        case .text: "text.viewfinder"
        case .qr: "qrcode"
        case .timer: "timer"
        case .mixer: "speaker.wave.2"
        }
    }
}

public enum IslandToolsStyle {
    public static let spring = Animation.spring(response: 0.44, dampingFraction: 0.88)
    public static let foreground = Color(red: 0.96, green: 0.96, blue: 0.97)
    public static let secondary = Color(red: 0.52, green: 0.52, blue: 0.56)
    public static let cell = Color(red: 0.09, green: 0.09, blue: 0.105)
    public static let green = Color(red: 0.65, green: 0.83, blue: 0.73)
}

@MainActor
@Observable
public final class IslandTools {
    public static let shared = IslandTools()

    public var active: IslandTool?
    public let countdown = IslandCountdown()
    public let ocr = IslandScreenText()
    public let qr = IslandQRCode()
    public let mixer = IslandAppMixer()

    @ObservationIgnored private weak var island: IslandState?
    @ObservationIgnored private var previousMode: IslandMode?
    @ObservationIgnored private var previousCompactStyle: CompactStyle?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    private init() {
        countdown.onFinished = { [weak self] in
            guard let self else { return }
            self.show(.timer)
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        ocr.onCompleted = { [weak self] in
            self?.show(.text)
        }
        qr.onCompleted = { [weak self] in
            self?.show(.qr)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mixer.shutdown()
            }
        }
    }

    public func attach(to state: IslandState) {
        guard island !== state else { return }
        island = state
        if countdown.hasBadge {
            ensureTimerIsVisible()
            if countdown.phase == .finished {
                show(.timer)
            }
        }
    }

    public func show(_ tool: IslandTool) {
        guard let island else { return }
        withAnimation(IslandToolsStyle.spring) {
            if active == nil {
                previousMode = island.mode
            }
            active = tool
            // Reuse the existing wide layout and window sizing.
            island.setMode(.apps)
            island.isHoverOpened = false
            island.setView(.open)
        }
        if tool == .mixer {
            mixer.startMonitoring()
        }
    }

    public func back() {
        guard let island else { return }
        withAnimation(IslandToolsStyle.spring) {
            active = nil
            if let previousMode {
                island.setMode(previousMode)
            }
            previousMode = nil
        }
    }

    public func leaveTools() {
        active = nil
        previousMode = nil
    }

    public func captureText() {
        show(.text)
        ocr.capture()
    }

    public func scanQRCode() {
        show(.qr)
        qr.scan()
    }

    public func startTimer(seconds: TimeInterval) {
        ensureTimerIsVisible()
        countdown.start(seconds: seconds)
    }

    public func resetTimer() {
        countdown.reset()
        if let island, let previousCompactStyle, island.compactStyle == .standard {
            island.setCompactStyle(previousCompactStyle)
        }
        previousCompactStyle = nil
    }

    private func ensureTimerIsVisible() {
        guard let island else { return }
        if island.compactStyle != .standard {
            if previousCompactStyle == nil {
                previousCompactStyle = island.compactStyle
            }
            island.setCompactStyle(.standard)
        }
    }
}

@MainActor
@Observable
public final class IslandCountdown {
    public enum Phase: String, Codable {
        case idle
        case running
        case paused
        case finished
    }

    private struct Snapshot: Codable {
        var phase: Phase
        var duration: TimeInterval
        var deadline: Date?
        var pausedRemaining: TimeInterval
    }

    public private(set) var phase: Phase = .idle
    public private(set) var duration: TimeInterval = 25 * 60
    public private(set) var now = Date()

    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var pausedRemaining: TimeInterval = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    private let storageKey = "island.native.countdown.v1"

    public var hasBadge: Bool { phase != .idle }
    public var remaining: TimeInterval {
        switch phase {
        case .idle: duration
        case .running: max(0, deadline?.timeIntervalSince(now) ?? 0)
        case .paused: pausedRemaining
        case .finished: 0
        }
    }

    public var progress: Double {
        guard duration > 0, phase != .idle else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    public var formattedRemaining: String {
        let value = max(0, Int(remaining.rounded(.up)))
        let hours = value / 3600
        let minutes = value / 60 % 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var status: String {
        switch phase {
        case .idle: "Выберите время"
        case .running: "Таймер идёт"
        case .paused: "На паузе"
        case .finished: "Время вышло"
        }
    }

    public init() {
        restore()
    }

    public func setDuration(_ seconds: TimeInterval) {
        guard phase == .idle, seconds.isFinite, seconds >= 1, seconds <= 86_400 else { return }
        duration = seconds
        save()
    }

    public func start(seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 1, seconds <= 86_400 else { return }
        ticker?.cancel()
        now = Date()
        duration = seconds
        deadline = now.addingTimeInterval(seconds)
        pausedRemaining = 0
        phase = .running
        save()
        startTicker()
    }

    public func pause() {
        guard phase == .running else { return }
        now = Date()
        pausedRemaining = remaining
        guard pausedRemaining > 0 else {
            finish()
            return
        }
        phase = .paused
        deadline = nil
        ticker?.cancel()
        ticker = nil
        save()
    }

    public func resume() {
        guard phase == .paused, pausedRemaining > 0 else { return }
        now = Date()
        deadline = now.addingTimeInterval(pausedRemaining)
        phase = .running
        save()
        startTicker()
    }

    public func reset() {
        ticker?.cancel()
        ticker = nil
        phase = .idle
        deadline = nil
        pausedRemaining = 0
        now = Date()
        save()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.now = Date()
                if self.phase != .running { return }
                if self.remaining <= 0 {
                    self.finish()
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func finish() {
        guard phase == .running else { return }
        phase = .finished
        deadline = nil
        pausedRemaining = 0
        ticker?.cancel()
        ticker = nil
        save()
        onFinished?()
    }

    private func save() {
        let snapshot = Snapshot(
            phase: phase,
            duration: duration,
            deadline: deadline,
            pausedRemaining: pausedRemaining
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.duration.isFinite,
              snapshot.duration >= 1,
              snapshot.duration <= 86_400 else { return }
        duration = snapshot.duration
        phase = snapshot.phase
        deadline = snapshot.deadline
        pausedRemaining = min(duration, max(0, snapshot.pausedRemaining))
        now = Date()
        if phase == .running {
            if deadline == nil || remaining <= 0 {
                phase = .finished
                deadline = nil
                save()
            } else {
                startTicker()
            }
        } else if phase == .paused && pausedRemaining <= 0 {
            phase = .finished
            save()
        }
    }
}
