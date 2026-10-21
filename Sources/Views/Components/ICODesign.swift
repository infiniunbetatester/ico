import SwiftUI

// Shared visual language. All surfaces use fills; there are no outline layers.
public enum ICODesign {
    public static let text = Color(red: 0.96, green: 0.96, blue: 0.98)
    public static let secondaryText = Color(red: 0.64, green: 0.65, blue: 0.70)
    public static let mutedText = Color(red: 0.46, green: 0.47, blue: 0.53)
    public static let accent = Color(red: 0.70, green: 0.63, blue: 1.0)

    public static func motion(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.40, dampingFraction: 0.88)
    }

    public static func quickMotion(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.10) : .spring(response: 0.25, dampingFraction: 0.84)
    }
}

/// Hover and press feedback shared by tabs, toolbar buttons and panel actions.
public struct ICOPressStyle: ButtonStyle {
    var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 11) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        ICOPressBody(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct ICOPressBody: View {
        let configuration: ButtonStyle.Configuration
        let cornerRadius: CGFloat
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.065 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
                .opacity(configuration.isPressed ? 0.80 : 1)
                .onHover { hovered = $0 }
                .animation(ICODesign.quickMotion(reduced: reduceMotion), value: hovered)
                .animation(ICODesign.quickMotion(reduced: reduceMotion), value: configuration.isPressed)
        }
    }
}

public struct ICOIconButton: View {
    let symbol: String
    let label: String
    let selected: Bool
    let rotation: Double
    let action: () -> Void

    public init(
        _ symbol: String,
        label: String,
        selected: Bool = false,
        rotation: Double = 0,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.label = label
        self.selected = selected
        self.rotation = rotation
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(rotation))
                .foregroundStyle(selected ? ICODesign.text : ICODesign.secondaryText)
                .frame(width: 28, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.13 : 0.035))
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ICOPressStyle(cornerRadius: 10))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "Включено" : "")
    }
}

/// Shared heading and spacing for the existing music/files/clipboard panels.
public struct ICOSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let trailingText: String?
    let content: Content

    public init(
        _ title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ICODesign.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ICODesign.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ICODesign.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.055), in: Capsule())
                }
            }
            content
        }
    }
}

/// A border-free reusable panel surface. Keep actual controls and data inside.
public struct ICOTile<Content: View>: View {
    let tint: Color
    let padding: CGFloat
    let content: Content

    public init(
        tint: Color = .white,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.065), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [tint.opacity(0.07), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 220
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

public struct ICOEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    public init(symbol: String, title: String, detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(ICODesign.accent)
                .frame(width: 48, height: 48)
                .background(ICODesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ICODesign.text)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(ICODesign.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct ICOEntranceValues {
    var opacity = 1.0
    var offset: CGFloat = 0
}

/// Animates a section change without .id(), preserving the wrapped view's identity.
public struct ICOSectionEntrance: ViewModifier {
    let selectionKey: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selectionKey: String) {
        self.selectionKey = selectionKey
    }

    public func body(content: Content) -> some View {
        content.keyframeAnimator(
            initialValue: ICOEntranceValues(),
            trigger: selectionKey
        ) { view, value in
            view
                .opacity(value.opacity)
                .offset(y: value.offset)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(reduceMotion ? 1.0 : 0.76, duration: 0.045)
                CubicKeyframe(1.0, duration: 0.20)
            }
            KeyframeTrack(\.offset) {
                LinearKeyframe(reduceMotion ? CGFloat.zero : 5, duration: 0.045)
                CubicKeyframe(CGFloat.zero, duration: 0.24)
            }
        }
    }
}
