import SwiftUI
import AppKit

/// Interactive gravitational drop portal inside the pulling liquid droplet.
public struct LiquidDropletPortalView: View {
    @Bindable var state: IslandState
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(time * 3.5) + 1.0) * 0.5 // 0.0 ... 1.0
            let targetActive = state.isDropletTargeted
            
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                
                // Suction Rings + Icon Core
                ZStack {
                    // Outer gravitational ripple
                    Circle()
                        .stroke(
                            (targetActive ? ICODesign.accent : Color.white).opacity(0.12 + (pulse * 0.16)),
                            lineWidth: 1.2
                        )
                        .frame(width: 38 + (pulse * 6), height: 38 + (pulse * 6))
                        .scaleEffect(targetActive ? 1.15 : 1.0)
                    
                    // Inner suction core
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    (targetActive ? ICODesign.accent : Color.white).opacity(targetActive ? 0.28 : 0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 18
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    // Central Portal Icon
                    Image(systemName: targetActive ? "tray.and.arrow.down.fill" : "arrow.down.to.line.compact")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(targetActive ? ICODesign.accent : Color(red: 0.94, green: 0.94, blue: 0.96))
                        .offset(y: targetActive ? (sin(time * 6.0) * 2.0) : 0)
                        .shadow(color: targetActive ? ICODesign.accent.opacity(0.6) : Color.clear, radius: 8)
                }
                .frame(height: 38)
                
                // Portal Label & Status
                HStack(spacing: 5) {
                    Text(targetActive ? "Отпустите для полки" : "Бросьте файл в полку")
                        .font(.system(size: 11, weight: targetActive ? .bold : .medium))
                        .foregroundColor(targetActive ? Color.white : Color(red: 0.82, green: 0.82, blue: 0.86))
                    
                    if !state.shelfFiles.isEmpty {
                        Text("\(state.shelfFiles.count)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(ICODesign.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay {
                // Flash bloom on absorption
                if state.dropletAbsorbFlash {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.85), ICODesign.accent.opacity(0.4), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        .transition(.opacity)
                }
            }
        }
    }
}
