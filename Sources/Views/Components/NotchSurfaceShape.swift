import SwiftUI

public struct NotchSurfaceShape: Shape {
    public var cornerRadius: CGFloat
    public var shoulderWidth: CGFloat = 16
    public var shoulderHeight: CGFloat = 14
    
    public var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }
    
    public init(cornerRadius: CGFloat = 30, shoulderWidth: CGFloat = 16, shoulderHeight: CGFloat = 14) {
        self.cornerRadius = cornerRadius
        self.shoulderWidth = shoulderWidth
        self.shoulderHeight = shoulderHeight
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let r = min(cornerRadius, h / 2.0)
        let sW = shoulderWidth
        let sH = min(shoulderHeight, h / 2.0)
        
        let leftBody = sW
        let rightBody = w - sW
        let c: CGFloat = 0.55228475 // Standard smooth circle/corner bezier coefficient
        
        // Start at top-left edge of the shoulder
        path.move(to: CGPoint(x: 0, y: 0))
        
        // Concave curve into the top-left of the main body
        path.addCurve(
            to: CGPoint(x: leftBody, y: sH),
            control1: CGPoint(x: leftBody - 4, y: 0),
            control2: CGPoint(x: leftBody, y: 0)
        )
        
        // Left vertical edge down to bottom-left corner
        path.addLine(to: CGPoint(x: leftBody, y: h - r))
        
        // Smooth bottom-left corner
        path.addCurve(
            to: CGPoint(x: leftBody + r, y: h),
            control1: CGPoint(x: leftBody, y: h - r * (1.0 - c)),
            control2: CGPoint(x: leftBody + r * (1.0 - c), y: h)
        )
        
        // Bottom horizontal straight edge
        path.addLine(to: CGPoint(x: rightBody - r, y: h))
        
        // Smooth bottom-right corner
        path.addCurve(
            to: CGPoint(x: rightBody, y: h - r),
            control1: CGPoint(x: rightBody - r * (1.0 - c), y: h),
            control2: CGPoint(x: rightBody, y: h - r * (1.0 - c))
        )
        
        // Right vertical edge up to shoulder
        path.addLine(to: CGPoint(x: rightBody, y: sH))
        
        // Concave curve out to top-right edge
        path.addCurve(
            to: CGPoint(x: w, y: 0),
            control1: CGPoint(x: rightBody, y: 0),
            control2: CGPoint(x: rightBody + 4, y: 0)
        )
        
        path.closeSubpath()
        return path
    }
}
