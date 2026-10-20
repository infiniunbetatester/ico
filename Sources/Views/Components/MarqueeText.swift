import SwiftUI

public struct MarqueeText: View {
    public let text: String
    public var font: Font = .system(size: 11, weight: .semibold)
    public var color: Color = Color.white.opacity(0.92)
    public var speed: Double = 28 // points per second
    public var spacing: CGFloat = 32
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?
    
    public init(
        text: String,
        font: Font = .system(size: 11, weight: .semibold),
        color: Color = Color.white.opacity(0.92),
        speed: Double = 28,
        spacing: CGFloat = 32
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.speed = speed
        self.spacing = spacing
    }
    
    public var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let needsScroll = textWidth > availableWidth && availableWidth > 0
            
            ZStack(alignment: .leading) {
                if needsScroll {
                    HStack(spacing: 0) {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .fixedSize()
                        
                        Text("      •      ")
                            .font(font)
                            .foregroundStyle(color.opacity(0.4))
                            .fixedSize()
                        
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .fixedSize()
                    }
                    .offset(x: offset)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: availableWidth, height: geo.size.height, alignment: .leading)
            .clipped()
            .mask(
                Group {
                    if needsScroll {
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 10)
                            
                            Rectangle().fill(Color.black)
                            
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 10)
                        }
                        .frame(width: availableWidth)
                    } else {
                        Rectangle().fill(Color.black)
                    }
                }
            )
            .onAppear {
                containerWidth = availableWidth
                measureAndStart(containerWidth: availableWidth)
            }
            .onChange(of: availableWidth) { _, newWidth in
                containerWidth = newWidth
                measureAndStart(containerWidth: newWidth)
            }
            .onChange(of: text) { _, _ in
                measureAndStart(containerWidth: containerWidth)
            }
        }
        .background(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { textGeo in
                        Color.clear.preference(
                            key: MarqueeTextWidthKey.self,
                            value: textGeo.size.width
                        )
                    }
                )
                .hidden()
        )
        .onPreferenceChange(MarqueeTextWidthKey.self) { newWidth in
            textWidth = newWidth
            measureAndStart(containerWidth: containerWidth)
        }
    }
    
    private func measureAndStart(containerWidth: CGFloat) {
        animationTask?.cancel()
        offset = 0
        
        guard textWidth > containerWidth, containerWidth > 0 else { return }
        
        // Measure loop width: textWidth + separator width (~48pt)
        let separatorWidth: CGFloat = 44
        let totalCycleDistance = textWidth + separatorWidth
        let duration = Double(totalCycleDistance) / speed
        
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -totalCycleDistance
            }
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
