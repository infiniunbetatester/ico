import SwiftUI

/// Smooth decorative playback indicator rendered on GPU via Canvas; minimal CPU footprint.
public struct ICOEqualizer: View {
    let tint: Color
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tint: Color, isActive: Bool) {
        self.tint = tint
        self.isActive = isActive
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isActive || reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = 4
                let gap: CGFloat = 2
                let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                for index in 0..<count {
                    let phase = Double(index) * 1.71
                    let wave = (sin(time * 4.0 + phase) + sin(time * 6.3 + phase * 0.65)) * 0.25 + 0.5
                    let amount = isActive && !reduceMotion ? wave : [0.35, 0.72, 0.52, 0.84][index]
                    let height = max(3, size.height * (0.22 + amount * 0.78))
                    let rect = CGRect(
                        x: CGFloat(index) * (width + gap),
                        y: (size.height - height) / 2,
                        width: width,
                        height: height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(tint))
                }
            }
        }
        .frame(width: 14, height: 13)
        .accessibilityHidden(true)
    }
}

/// Fallback or real artwork renderer
public struct ICOArtwork: View {
    let image: Image?
    let tint: Color
    let size: CGFloat

    public init(image: Image? = nil, tint: Color, size: CGFloat) {
        self.image = image
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        ZStack {
            if let image {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [tint, tint.opacity(0.30), Color(red: 0.12, green: 0.10, blue: 0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .blur(radius: size * 0.16)
                    .offset(x: -size * 0.24, y: -size * 0.30)
                Ellipse()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: size * 1.25, height: size * 0.65)
                    .rotationEffect(.degrees(-35))
                    .offset(x: size * 0.16, y: size * 0.24)
                Image(systemName: "music.note")
                    .font(.system(size: max(8, size * 0.26), weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(3.5, size * 0.22), style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct ICOTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Scrolls ONLY when text overflows the container. Pauses timeline when fitting.
public struct ICOMarqueeText: View {
    let text: String
    let isActive: Bool
    let font: Font
    let color: Color
    @State private var measuredWidth: CGFloat = 0
    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ text: String,
        isActive: Bool = true,
        font: Font = .system(size: 10, weight: .medium, design: .rounded),
        color: Color = Color.white.opacity(0.92)
    ) {
        self.text = text
        self.isActive = isActive
        self.font = font
        self.color = color
    }

    public var body: some View {
        GeometryReader { geometry in
            let overflow = measuredWidth > geometry.size.width + 1
            let moving = overflow && isActive && !reduceMotion
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                let gap: CGFloat = 28
                let distance = measuredWidth + gap
                let duration = Double(distance / 24)
                let elapsed = max(0, timeline.date.timeIntervalSince(epoch))
                let phase = elapsed.truncatingRemainder(dividingBy: max(1, duration + 1.6))
                let offset = moving ? min(distance, CGFloat(max(0, phase - 1.6)) * 24) : 0
                HStack(spacing: gap) {
                    label
                    if overflow { label.accessibilityHidden(true) }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: -offset)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: moving ? .leading : .center)
                .clipped()
                .mask {
                    if overflow {
                        LinearGradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.88),
                            .init(color: .clear, location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    } else { Color.white }
                }
            }
        }
        .background(alignment: .leading) {
            label.fixedSize()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ICOTextWidthKey.self, value: proxy.size.width)
                })
                .hidden()
        }
        .onPreferenceChange(ICOTextWidthKey.self) { measuredWidth = $0 }
        .onChange(of: text) { _, _ in epoch = Date() }
        .onChange(of: isActive) { _, _ in epoch = Date() }
        .onAppear { epoch = Date() }
        .frame(height: 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(color)
    }
}

/// Visual countdown badge with animated number transitions
public struct ICOCountdownBadge: View {
    let secondsRemaining: Int
    let isPaused: Bool
    let tint: Color

    public init(secondsRemaining: Int, isPaused: Bool = false, tint: Color = Color(red: 0.65, green: 0.83, blue: 0.73)) {
        self.secondsRemaining = max(0, secondsRemaining)
        self.isPaused = isPaused
        self.tint = tint
    }

    private var timeString: String {
        let hours = secondsRemaining / 3600
        let minutes = (secondsRemaining / 60) % 60
        let seconds = secondsRemaining % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isPaused ? "pause.fill" : "timer")
                .font(.system(size: 9, weight: .semibold))
            Text(timeString)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(tint.opacity(0.14), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Таймер, \(timeString)\(isPaused ? ", пауза" : "")")
    }
}
