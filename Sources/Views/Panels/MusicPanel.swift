import SwiftUI

public struct MusicPanel: View {
    @Bindable var state: IslandState
    @State private var isDraggingSeek: Bool = false
    @State private var dragElapsed: Double = 0
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Main Top: Cover Art + Info + Controls
            HStack(alignment: .top, spacing: 21) {
                // Cover Art (Real video/music artwork or luxury vinyl placeholder)
                ZStack {
                    if let data = UniversalMediaController.shared.currentTrack?.artworkData,
                       let nsImg = NSImage(data: data) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 114, height: 114)
                    } else {
                        // Sleek obsidian vinyl disc card
                        ZStack {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.14, green: 0.14, blue: 0.16),
                                            Color(red: 0.08, green: 0.08, blue: 0.09)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            // Vinyl subtle concentric rings
                            Circle()
                                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                                .frame(width: 90, height: 90)
                            Circle()
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                .frame(width: 66, height: 66)
                            Circle()
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                .frame(width: 42, height: 42)
                            
                            // Center label
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: state.isPlaying ? [
                                            Color(red: 0.95, green: 0.45, blue: 0.35),
                                            Color(red: 0.85, green: 0.25, blue: 0.4)
                                        ] : [
                                            Color(red: 0.3, green: 0.32, blue: 0.36),
                                            Color(red: 0.18, green: 0.2, blue: 0.22)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                                        .frame(width: 8, height: 8)
                                )
                        }
                    }
                }
                .frame(width: 114, height: 114)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 6)
                
                // Track Info & Transport
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.activePlayerApp?.uppercased() ?? (state.isPlaying ? "СЕЙЧАС ИГРАЕТ" : "МЕДИА"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.52, green: 0.52, blue: 0.56))
                                .tracking(0.7)
                            
                            Text(state.trackTitle)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.98))
                                .lineLimit(1)
                            
                            Text(state.trackArtist)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(Color(red: 0.62, green: 0.62, blue: 0.66))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button(action: { state.toggleFavorite() }) {
                            Image(systemName: state.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(state.isFavorite ? Color(red: 1.0, green: 0.41, blue: 0.49) : Color(red: 0.53, green: 0.53, blue: 0.56))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer(minLength: 12)
                    
                    // Transport Bar
                    HStack(spacing: 24) {
                        // Shuffle
                        Button(action: { state.toggleShuffle() }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(state.isShuffle ? Color(red: 0.84, green: 0.84, blue: 0.86) : Color(red: 0.35, green: 0.35, blue: 0.38))
                        }
                        .buttonStyle(.plain)
                        
                        // Previous
                        Button(action: { state.previousTrack() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.79, green: 0.79, blue: 0.82))
                        }
                        .buttonStyle(.plain)
                        
                        // Play/Pause button
                        Button(action: { state.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.95, green: 0.95, blue: 0.97))
                                    .frame(width: 42, height: 42)
                                
                                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(red: 0.03, green: 0.03, blue: 0.04))
                                    .offset(x: state.isPlaying ? 0 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Next
                        Button(action: { state.nextTrack() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.79, green: 0.79, blue: 0.82))
                        }
                        .buttonStyle(.plain)
                        
                        // Repeat
                        Button(action: { state.toggleRepeat() }) {
                            Image(systemName: "repeat")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(state.isRepeat ? Color(red: 0.84, green: 0.84, blue: 0.86) : Color(red: 0.35, green: 0.35, blue: 0.38))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 292)
                }
            }
            .padding(.top, 4)
            
            // Timeline Scrubber
            HStack(spacing: 11) {
                Text(isDraggingSeek ? formatTime(dragElapsed) : state.formattedElapsed)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.47))
                    .frame(width: 32, alignment: .leading)
                
                GeometryReader { geo in
                    let curr = isDraggingSeek ? dragElapsed : state.elapsed
                    let frac = state.duration > 0 ? curr / state.duration : 0.0
                    
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 0.16, green: 0.16, blue: 0.18))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(Color(red: 0.85, green: 0.85, blue: 0.88))
                            .frame(width: max(0, min(geo.size.width * CGFloat(frac), geo.size.width)), height: 4)
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                isDraggingSeek = true
                                let ratio = max(0, min(val.location.x / geo.size.width, 1.0))
                                dragElapsed = ratio * state.duration
                            }
                            .onEnded { val in
                                let ratio = max(0, min(val.location.x / geo.size.width, 1.0))
                                state.seek(to: ratio * state.duration)
                                isDraggingSeek = false
                            }
                    )
                }
                .frame(height: 14)
                
                Text(state.formattedRemaining)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.47))
                    .frame(width: 38, alignment: .trailing)
            }
            
            // Footer: Media Source & Volume
            // Footer: Media Source & Volume
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(state.isPlaying ? Color(red: 0.22, green: 0.85, blue: 0.52) : Color(red: 0.45, green: 0.45, blue: 0.48))
                        .frame(width: 6, height: 6)
                    
                    Text(state.activePlayerApp ?? (state.isPlaying ? "Медиа" : "Звук macOS"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.62, green: 0.62, blue: 0.66))
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(action: {
                        if state.volume > 0 { state.setVolumeValue(0) }
                        else { state.setVolumeValue(65) }
                    }) {
                        Image(systemName: state.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                    }
                    .buttonStyle(.plain)
                    
                    Slider(
                        value: Binding(
                            get: { state.volume },
                            set: { state.setVolumeValue($0) }
                        ),
                        in: 0...100
                    )
                    .frame(width: 105)
                    .tint(Color(red: 0.85, green: 0.85, blue: 0.88))
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(width: 640)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
