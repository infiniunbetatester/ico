import SwiftUI

@MainActor struct LiquidDropSurface: View {
    let session: LiquidDropSession
    let configuration: LiquidDropConfiguration
    let normal: AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let visible = session.showsDroplet && !configuration.isExpanded()
        ZStack(alignment: .top) {
            normal.opacity(visible ? 0 : 1)
            LiquidDropletView(session: session)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: configuration.receiverSize.width, height: configuration.receiverSize.height, alignment: .top)
        .ignoresSafeArea(.container, edges: .all)
        .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.16), value: visible)
    }
}

public struct LiquidDropletView: View {
    public let session: LiquidDropSession
    public init(session: LiquidDropSession) { self.session = session }

    public var body: some View {
        GeometryReader { proxy in
            let amount = min(1, session.pull / 64)
            let radius = 28 * amount
            let center = CGPoint(x: proxy.size.width / 2 + session.offsetX * amount,
                                 y: session.metrics.bodyHeight + session.pull - radius)
            let shape = LiquidNotchDropletShape(metrics: session.metrics, pull: session.pull, offsetX: session.offsetX)
            ZStack {
                shape
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.30), radius: 16, x: 0, y: 10)
                RadialGradient(
                    colors: [Color.white.opacity(session.targeted ? 0.095 : 0.035), .clear],
                    center: UnitPoint(x: center.x / max(1, proxy.size.width), y: center.y / max(1, proxy.size.height)),
                    startRadius: 0, endRadius: 38
                )
                .clipShape(shape)
                ZStack {
                    Circle().fill(Color.white.opacity(session.targeted ? 0.11 : 0.045))
                    Image(systemName: session.phase == .absorbing ? "checkmark" : "tray.and.arrow.down.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(session.targeted ? 0.95 : 0.60))
                }
                .frame(width: 34, height: 34)
                .scaleEffect((0.75 + amount * 0.25) * (1 - session.absorbProgress * 0.4))
                .opacity(amount * (1 - session.absorbProgress))
                .position(x: center.x, y: center.y - session.absorbProgress * 9)
            }
        }
        .accessibilityHidden(true)
    }
}
