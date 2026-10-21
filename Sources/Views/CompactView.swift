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
                        .fill(Color.white.opacity(isHovered ? 0.35 : 0.18))
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
            if tools.countdown.phase == .finished {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Готово")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(IslandToolsStyle.green)
            } else {
                ICOCountdownBadge(
                    secondsRemaining: max(0, Int(tools.countdown.remaining.rounded(.up))),
                    isPaused: tools.countdown.phase == .paused,
                    tint: timerColor
                )
            }

            Spacer(minLength: 6)

            // Progress bar
            Capsule()
                .fill(timerColor.opacity(0.7))
                .frame(
                    width: max(
                        0,
                        (state.targetWidth - 40) * tools.countdown.progress
                    ),
                    height: 2
                )
        }
        .padding(.horizontal, 14)
        .frame(
            width: state.targetWidth,
            height: state.targetHeight
        )
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
        HStack(spacing: 7) {
            if state.isPlaying {
                // Real album cover art (or stylized music pill)
                artworkView
                
                // Smart animated Marquee running track title & artist (only scrolls if overflowing, centered if fits)
                let trackInfo = state.trackArtist.isEmpty || state.trackArtist == state.activePlayerApp
                    ? state.trackTitle
                    : "\(state.trackTitle)  —  \(state.trackArtist)"
                
                ICOMarqueeText(
                    trackInfo,
                    isActive: state.isPlaying,
                    font: .system(size: 11.5, weight: .semibold, design: .rounded),
                    color: Color.white.opacity(0.95)
                )
                .frame(maxWidth: .infinity)

                // Smooth GPU Canvas Equalizer with sine waves at 24 fps
                ICOEqualizer(tint: state.auraSwiftUIColor, isActive: state.isPlaying)
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
        .padding(.horizontal, 9)
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
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                ICOArtwork(tint: state.auraSwiftUIColor, size: 18)
            }
        }
    }
}
