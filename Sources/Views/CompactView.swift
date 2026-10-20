import SwiftUI

public struct CompactView: View {
    @Bindable var state: IslandState
    var onTap: () -> Void
    @State private var tools = IslandTools.shared
    @State private var isHovered = false

    public init(
        state: IslandState,
        onTap: @escaping () -> Void
    ) {
        self.state = state
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            if tools.countdown.hasBadge {
                tools.show(.timer)
            } else {
                onTap()
            }
        } label: {
            ZStack {
                if tools.countdown.hasBadge {
                    timerContent
                } else if state.compactStyle == .minimal {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(
                            width: isHovered ? 140 : 100,
                            height: 4
                        )
                        .padding(.top, 1)
                } else if state.compactStyle == .standard {
                    musicContent
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(
            IslandToolsStyle.spring,
            value: isHovered
        )
    }

    private var timerContent: some View {
        HStack(spacing: 8) {
            Image(systemName: timerIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(timerColor)

            Spacer(minLength: 6)

            Text(
                tools.countdown.phase == .finished ? "Готово" : tools.countdown.formattedRemaining
            )
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(timerColor)
            .contentTransition(.numericText(countsDown: true))
        }
        .padding(.horizontal, 16)
        .frame(
            width: state.targetWidth,
            height: state.targetHeight
        )
        .overlay(alignment: .bottomLeading) {
            Capsule()
                .fill(timerColor.opacity(0.65))
                .frame(
                    width: max(
                        0,
                        (state.targetWidth - 32) * tools.countdown.progress
                    ),
                    height: 1.5
                )
                .padding(.leading, 16)
                .padding(.bottom, 3)
        }
        .animation(
            .linear(duration: 0.25),
            value: tools.countdown.progress
        )
    }

    private var timerIcon: String {
        switch tools.countdown.phase {
        case .paused:
            "pause.fill"
        case .finished:
            "checkmark"
        default:
            "timer"
        }
    }

    private var timerColor: Color {
        switch tools.countdown.phase {
        case .paused:
            Color(red: 0.89, green: 0.73, blue: 0.46)
        case .finished:
            IslandToolsStyle.green
        default:
            Color.white.opacity(0.88)
        }
    }

    private var musicContent: some View {
        HStack(spacing: 6) {
            if state.isPlaying {
                // Real album cover art (or stylized music pill)
                artworkView
                
                // Animated Marquee running track title & artist
                MarqueeText(
                    text: state.trackArtist.isEmpty || state.trackArtist == state.activePlayerApp
                        ? state.trackTitle
                        : "\(state.trackTitle)  —  \(state.trackArtist)",
                    font: .system(size: 10, weight: .medium, design: .rounded),
                    color: Color.white.opacity(0.92),
                    speed: 24
                )
                .frame(maxWidth: .infinity)

                // Audio visualizer bars tinted dynamically in album cover's aura color
                visualizerView
            } else {
                Spacer()
                if isHovered {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                        Text("Dynamic Notch")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 3)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(
            width: state.targetWidth,
            height: state.targetHeight
        )
    }

    private var artworkView: some View {
        ZStack {
            if let img = state.artworkImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    state.auraSwiftUIColor.opacity(0.9),
                                    state.auraSwiftUIColor.opacity(0.55)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 16, height: 16)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
        }
    }

    private var visualizerView: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { index in
                let value = state.visualizerBars.indices.contains(index)
                    ? CGFloat(state.visualizerBars[index])
                    : 0.2
                RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                    .fill(state.auraSwiftUIColor)
                    .frame(
                        width: 1.8,
                        height: max(2.5, value * 7 + 2)
                    )
            }
        }
        .frame(width: 13, height: 13)
    }
}
