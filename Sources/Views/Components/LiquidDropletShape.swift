import SwiftUI

/// An animatable shape that morphs from a standard Mac notch surface
/// into an organic liquid droplet pulling downward under gravity.
public struct LiquidDropletShape: Shape {
    public var cornerRadius: CGFloat
    public var shoulderWidth: CGFloat
    public var shoulderHeight: CGFloat
    public var stretchFactor: CGFloat // 0.0 (normal notch) ... 1.0 (fully stretched liquid drop)

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(cornerRadius, AnimatablePair(shoulderWidth, AnimatablePair(shoulderHeight, stretchFactor)))
        }
        set {
            cornerRadius = newValue.first
            shoulderWidth = newValue.second.first
            shoulderHeight = newValue.second.second.first
            stretchFactor = newValue.second.second.second
        }
    }

    public init(
        cornerRadius: CGFloat = 30,
        shoulderWidth: CGFloat = 16,
        shoulderHeight: CGFloat = 14,
        stretchFactor: CGFloat = 0.0
    ) {
        self.cornerRadius = cornerRadius
        self.shoulderWidth = shoulderWidth
        self.shoulderHeight = shoulderHeight
        self.stretchFactor = stretchFactor
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        
        let sf = min(max(0, stretchFactor), 1.0)
        let sw = min(max(0, shoulderWidth), rect.width * 0.24)
        let sh = min(max(0, shoulderHeight), rect.height * 0.45)
        let left = rect.minX + sw
        let right = rect.maxX - sw
        let top = rect.minY
        let bottom = rect.maxY
        let c: CGFloat = 0.55228475
        
        // If stretchFactor is virtually zero, use standard notch path
        if sf < 0.005 {
            let radius = min(max(0, cornerRadius), (right - left) * 0.5, rect.height - sh)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addCurve(
                to: CGPoint(x: left, y: top + sh),
                control1: CGPoint(x: rect.minX + sw * 0.60, y: top),
                control2: CGPoint(x: left, y: top + sh * 0.08)
            )
            path.addLine(to: CGPoint(x: left, y: bottom - radius))
            path.addCurve(
                to: CGPoint(x: left + radius, y: bottom),
                control1: CGPoint(x: left, y: bottom - radius + radius * c),
                control2: CGPoint(x: left + radius - radius * c, y: bottom)
            )
            path.addLine(to: CGPoint(x: right - radius, y: bottom))
            path.addCurve(
                to: CGPoint(x: right, y: bottom - radius),
                control1: CGPoint(x: right - radius + radius * c, y: bottom),
                control2: CGPoint(x: right, y: bottom - radius + radius * c)
            )
            path.addLine(to: CGPoint(x: right, y: top + sh))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: top),
                control1: CGPoint(x: right, y: top + sh * 0.08),
                control2: CGPoint(x: rect.maxX - sw * 0.60, y: top)
            )
            path.closeSubpath()
            return path
        }
        
        // Liquid droplet geometry:
        // - Top shoulders fixed to bezel.
        // - Waist pinches inward gracefully.
        // - Lower bulb expands into a full, rounded drop.
        let waistPinch = min((right - left) * 0.14, 20.0) * sf
        let waistY = top + sh + max(6.0, (bottom - top - sh) * 0.35)
        let waistLeft = left + waistPinch
        let waistRight = right - waistPinch
        
        let bulbRadius = min(max(16, cornerRadius), (right - left) * 0.5, (bottom - waistY) * 0.85)
        let bulbTopY = max(waistY + 4, bottom - bulbRadius)
        let bulbLeft = left
        let bulbRight = right
        
        var path = Path()
        // Top-left shoulder
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addCurve(
            to: CGPoint(x: left, y: top + sh),
            control1: CGPoint(x: rect.minX + sw * 0.60, y: top),
            control2: CGPoint(x: left, y: top + sh * 0.08)
        )
        
        // Inward curve to waist
        path.addCurve(
            to: CGPoint(x: waistLeft, y: waistY),
            control1: CGPoint(x: left, y: top + sh + (waistY - top - sh) * 0.5),
            control2: CGPoint(x: waistLeft + waistPinch * 0.15, y: waistY - (waistY - top - sh) * 0.3)
        )
        
        // Outward curve from waist to bulb
        path.addCurve(
            to: CGPoint(x: bulbLeft, y: bulbTopY),
            control1: CGPoint(x: waistLeft - waistPinch * 0.15, y: waistY + (bulbTopY - waistY) * 0.3),
            control2: CGPoint(x: bulbLeft, y: bulbTopY - (bulbTopY - waistY) * 0.4)
        )
        
        // Bulb bottom-left rounded corner
        path.addCurve(
            to: CGPoint(x: bulbLeft + bulbRadius, y: bottom),
            control1: CGPoint(x: bulbLeft, y: bottom - bulbRadius + bulbRadius * c),
            control2: CGPoint(x: bulbLeft + bulbRadius - bulbRadius * c, y: bottom)
        )
        
        // Bulb bottom line
        path.addLine(to: CGPoint(x: bulbRight - bulbRadius, y: bottom))
        
        // Bulb bottom-right rounded corner
        path.addCurve(
            to: CGPoint(x: bulbRight, y: bulbTopY),
            control1: CGPoint(x: bulbRight - bulbRadius + bulbRadius * c, y: bottom),
            control2: CGPoint(x: bulbRight, y: bottom - bulbRadius + bulbRadius * c)
        )
        
        // Inward curve from bulb up to waist
        path.addCurve(
            to: CGPoint(x: waistRight, y: waistY),
            control1: CGPoint(x: bulbRight, y: bulbTopY - (bulbTopY - waistY) * 0.4),
            control2: CGPoint(x: waistRight - waistPinch * 0.15, y: waistY + (bulbTopY - waistY) * 0.3)
        )
        
        // Outward curve from waist up to right shoulder
        path.addCurve(
            to: CGPoint(x: right, y: top + sh),
            control1: CGPoint(x: waistRight + waistPinch * 0.15, y: waistY - (waistY - top - sh) * 0.3),
            control2: CGPoint(x: right, y: top + sh + (waistY - top - sh) * 0.5)
        )
        
        // Top-right shoulder back to screen edge
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: top),
            control1: CGPoint(x: right, y: top + sh * 0.08),
            control2: CGPoint(x: rect.maxX - sw * 0.60, y: top)
        )
        
        path.closeSubpath()
        return path
    }
}
