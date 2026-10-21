import SwiftUI
import Foundation

/// Keep this key stable across application updates.
public enum ICOFirstLaunch {
    public static let storageKey = "ico.onboarding.welcome.completed.v1"
    public static let didComplete = Notification.Name("ico.onboarding.welcome.completed")

    /// Check if onboarding is needed
    public static var isRequired: Bool {
        !UserDefaults.standard.bool(forKey: storageKey)
    }
}

public enum ICOWelcomeMetrics {
    public static let contentWidth: CGFloat = 520
    public static let height: CGFloat = 320
    public static let cornerRadius: CGFloat = 30
    public static let shoulderWidth: CGFloat = 16
    public static let fullWidth = contentWidth + shoulderWidth * 2
}

/// First-launch content only; the existing island provides its outer surface.
public struct ICOWelcomeView: View {
    let onStart: () -> Void
    @State private var ink: CGFloat = 0
    @State private var controlsVisible = false
    @State private var lightVisible = false
    @State private var didStartAnimation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    public var body: some View {
        VStack(spacing: 0) {
            ICOHelloInk(progress: reduceMotion ? 1 : ink)
                .fill(Color(red: 0.97, green: 0.965, blue: 0.98))
                .frame(width: 268, height: 98)
                .padding(.top, 66)
                .accessibilityHidden(true)

            Text("Добро пожаловать в ICO")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ICODesign.secondaryText)
                .padding(.top, 18)
                .opacity(controlsVisible || reduceMotion ? 1 : 0)
                .offset(y: controlsVisible || reduceMotion ? 0 : 5)

            Button(action: onStart) {
                HStack(spacing: 14) {
                    Text("Начать работу")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.075, blue: 0.10))
                .frame(width: 190, height: 40)
                .background(
                    Color(red: 0.94, green: 0.93, blue: 0.96),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(ICOPressStyle(cornerRadius: 13))
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Закрыть приветствие и открыть приложение")
            .padding(.top, 22)
            .opacity(controlsVisible || reduceMotion ? 1 : 0)
            .offset(y: controlsVisible || reduceMotion ? 0 : 6)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .center) {
            RadialGradient(
                colors: [
                    ICODesign.accent.opacity(lightVisible ? 0.065 : 0),
                    Color(red: 0.80, green: 0.70, blue: 0.87).opacity(lightVisible ? 0.018 : 0),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.56),
                startRadius: 0,
                endRadius: 240
            )
            .padding(.top, 36)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hello. Добро пожаловать")
        .task(id: reduceMotion) {
            if reduceMotion {
                ink = 1
                controlsVisible = true
                lightVisible = true
                return
            }
            guard !didStartAnimation else { return }
            didStartAnimation = true
            do {
                try await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 1.15)) { lightVisible = true }
                withAnimation(.linear(duration: 2.05)) { ink = 1 }
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.42)) { controlsVisible = true }
            } catch {
                // Task cancelled
            }
        }
    }
}

/// A connected handwritten word, independent of fonts, images and screen scale.
public struct ICOHelloInk: Shape {
    public var progress: CGFloat

    public init(progress: CGFloat = 1) { self.progress = progress }

    public var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0, progress > 0 else { return Path() }
        let pen = Self.penPath
        let bounds = pen.boundingRect.insetBy(dx: -6, dy: -6)
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let filledInk = pen
            .trimmedPath(from: 0, to: min(1, max(0, progress)))
            .strokedPath(StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
        return filledInk.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - bounds.midX * scale,
            ty: rect.midY - bounds.midY * scale
        ))
    }

    private static var penPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 61, y: 181))
        // h — entry, ascender loop, stem and shoulder.
        p.addCurve(to: CGPoint(x: 119, y: 128), control1: CGPoint(x: 79, y: 171), control2: CGPoint(x: 102, y: 156))
        p.addCurve(to: CGPoint(x: 125, y: 78), control1: CGPoint(x: 131, y: 108), control2: CGPoint(x: 137, y: 83))
        p.addCurve(to: CGPoint(x: 104, y: 113), control1: CGPoint(x: 113, y: 72), control2: CGPoint(x: 107, y: 96))
        p.addCurve(to: CGPoint(x: 94, y: 186), control1: CGPoint(x: 99, y: 140), control2: CGPoint(x: 94, y: 170))
        p.addCurve(to: CGPoint(x: 118, y: 139), control1: CGPoint(x: 99, y: 167), control2: CGPoint(x: 104, y: 142))
        p.addCurve(to: CGPoint(x: 136, y: 165), control1: CGPoint(x: 133, y: 136), control2: CGPoint(x: 139, y: 149))
        p.addCurve(to: CGPoint(x: 169, y: 184), control1: CGPoint(x: 130, y: 187), control2: CGPoint(x: 146, y: 195))
        // e — a low loop joining the first tall l.
        p.addCurve(to: CGPoint(x: 203, y: 142), control1: CGPoint(x: 191, y: 176), control2: CGPoint(x: 206, y: 160))
        p.addCurve(to: CGPoint(x: 178, y: 143), control1: CGPoint(x: 201, y: 126), control2: CGPoint(x: 184, y: 127))
        p.addCurve(to: CGPoint(x: 186, y: 186), control1: CGPoint(x: 168, y: 165), control2: CGPoint(x: 172, y: 181))
        // l, l — two separate loops with a flowing baseline.
        p.addCurve(to: CGPoint(x: 257, y: 140), control1: CGPoint(x: 212, y: 198), control2: CGPoint(x: 242, y: 171))
        p.addCurve(to: CGPoint(x: 261, y: 78), control1: CGPoint(x: 275, y: 106), control2: CGPoint(x: 274, y: 76))
        p.addCurve(to: CGPoint(x: 236, y: 153), control1: CGPoint(x: 245, y: 79), control2: CGPoint(x: 237, y: 122))
        p.addCurve(to: CGPoint(x: 249, y: 187), control1: CGPoint(x: 232, y: 174), control2: CGPoint(x: 236, y: 186))
        p.addCurve(to: CGPoint(x: 315, y: 128), control1: CGPoint(x: 274, y: 190), control2: CGPoint(x: 298, y: 161))
        p.addCurve(to: CGPoint(x: 316, y: 78), control1: CGPoint(x: 330, y: 100), control2: CGPoint(x: 330, y: 77))
        p.addCurve(to: CGPoint(x: 289, y: 152), control1: CGPoint(x: 302, y: 79), control2: CGPoint(x: 291, y: 116))
        p.addCurve(to: CGPoint(x: 304, y: 187), control1: CGPoint(x: 287, y: 174), control2: CGPoint(x: 291, y: 185))
        p.addCurve(to: CGPoint(x: 354, y: 144), control1: CGPoint(x: 325, y: 190), control2: CGPoint(x: 348, y: 172))
        // o and the final upward flourish.
        p.addCurve(to: CGPoint(x: 365, y: 188), control1: CGPoint(x: 341, y: 163), control2: CGPoint(x: 345, y: 184))
        p.addCurve(to: CGPoint(x: 391, y: 148), control1: CGPoint(x: 389, y: 196), control2: CGPoint(x: 400, y: 171))
        p.addCurve(to: CGPoint(x: 354, y: 144), control1: CGPoint(x: 384, y: 130), control2: CGPoint(x: 364, y: 128))
        p.addCurve(to: CGPoint(x: 419, y: 132), control1: CGPoint(x: 373, y: 134), control2: CGPoint(x: 398, y: 151))
        return p
    }
}
