import CoreGraphics
import Foundation

// Dyogène, the character: an old sage after Diogenes, the philosopher who lived in a jar and
// walked in daylight with a lantern "looking for a man". Bald dome, white tufts over the ears, a
// long cloud of a beard, a teal robe, and a lantern held up. His one quirk: the left eyebrow,
// always a little raised. Curious, a bit wry, never mean.
//
// Drawn in plain Core Graphics on a 100 × 100 grid (y down) so the app and the icon renderer
// (scripts/render-icon.swift) share one drawing. Colours are fixed: he looks the same in light
// and dark mode, like a figure on a painted jar. See docs/DESIGN.md, "The character".

enum DyogeneExpression: Sendable {
    /// Eyes open, small smile.
    case calm
    /// Left brow high, eyes a little wider: "is that so?"
    case curious
    /// Eyes closed in a smile.
    case pleased
    /// Eyes turned to his lantern, looking around.
    case searching
}

enum DyogeneArt {
    static let ink = CGColor(srgbRed: 0.11, green: 0.13, blue: 0.25, alpha: 1)       // night indigo, a bit deeper
    static let skin = CGColor(srgbRed: 0.91, green: 0.76, blue: 0.62, alpha: 1)
    static let skinShade = CGColor(srgbRed: 0.82, green: 0.64, blue: 0.50, alpha: 1)
    static let beard = CGColor(srgbRed: 0.96, green: 0.94, blue: 0.89, alpha: 1)      // marble
    static let beardShade = CGColor(srgbRed: 0.84, green: 0.80, blue: 0.73, alpha: 1)
    static let robe = CGColor(srgbRed: 0.31, green: 0.55, blue: 0.52, alpha: 1)       // patina
    static let robeShade = CGColor(srgbRed: 0.22, green: 0.42, blue: 0.40, alpha: 1)
    static let strap = CGColor(srgbRed: 0.73, green: 0.68, blue: 0.61, alpha: 1)      // dust
    static let lanternMetal = CGColor(srgbRed: 0.24, green: 0.22, blue: 0.30, alpha: 1)
    static let flame = CGColor(srgbRed: 1.0, green: 0.90, blue: 0.66, alpha: 1)        // glow
    static let amber = CGColor(srgbRed: 0.95, green: 0.70, blue: 0.24, alpha: 1)       // lantern

    /// Draws him into `rect` (a square works best). `context` must be y-down (flipped).
    static func draw(in context: CGContext, rect: CGRect, expression: DyogeneExpression = .calm,
                     glow: Bool = true, detailed: Bool = true) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 100, y: rect.height / 100)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        let line: CGFloat = detailed ? 1.7 : 2.6

        if glow { drawGlow(context) }
        drawRobe(context, line: line)
        drawArm(context, line: line)
        drawHead(context, line: line)
        drawBeard(context, line: line, detailed: detailed)
        drawFace(context, expression: expression, line: line, detailed: detailed)
        drawLantern(context, line: line, detailed: detailed)
        context.restoreGState()
    }

    // MARK: Parts

    private static func drawGlow(_ c: CGContext) {
        let colors = [amber.copy(alpha: 0.55)!, amber.copy(alpha: 0.18)!, amber.copy(alpha: 0)!] as CFArray
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.4, 1]) else { return }
        // Kept inside the 100-point square so it never shows a clipped edge.
        let center = CGPoint(x: 19.5, y: 64)
        c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 19, options: [])
    }

    private static func fillAndStroke(_ c: CGContext, _ path: CGPath, fill: CGColor, line: CGFloat) {
        c.addPath(path)
        c.setFillColor(fill)
        c.fillPath()
        c.addPath(path)
        c.setStrokeColor(ink)
        c.setLineWidth(line)
        c.strokePath()
    }

    private static func drawRobe(_ c: CGContext, line: CGFloat) {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 12, y: 100))
        body.addCurve(to: CGPoint(x: 34, y: 76), control1: CGPoint(x: 13, y: 88), control2: CGPoint(x: 22, y: 78))
        body.addLine(to: CGPoint(x: 66, y: 76))
        body.addCurve(to: CGPoint(x: 88, y: 100), control1: CGPoint(x: 78, y: 78), control2: CGPoint(x: 87, y: 88))
        body.closeSubpath()
        fillAndStroke(c, body, fill: robe, line: line)
        // The himation's fold, over the left shoulder.
        let fold = CGMutablePath()
        fold.move(to: CGPoint(x: 66, y: 77))
        fold.addCurve(to: CGPoint(x: 46, y: 100), control1: CGPoint(x: 64, y: 88), control2: CGPoint(x: 54, y: 95))
        fold.addLine(to: CGPoint(x: 62, y: 100))
        fold.addCurve(to: CGPoint(x: 74, y: 79), control1: CGPoint(x: 68, y: 93), control2: CGPoint(x: 73, y: 86))
        fold.closeSubpath()
        fillAndStroke(c, fold, fill: strap, line: line)
    }

    private static func drawArm(_ c: CGContext, line: CGFloat) {
        // The sleeve rises from the shoulder to the hand holding the lantern.
        let sleeve = CGMutablePath()
        sleeve.move(to: CGPoint(x: 16, y: 96))
        sleeve.addCurve(to: CGPoint(x: 14, y: 80), control1: CGPoint(x: 12, y: 90), control2: CGPoint(x: 12, y: 84))
        sleeve.addLine(to: CGPoint(x: 25, y: 79))
        sleeve.addCurve(to: CGPoint(x: 31, y: 92), control1: CGPoint(x: 27, y: 84), control2: CGPoint(x: 30, y: 88))
        sleeve.closeSubpath()
        fillAndStroke(c, sleeve, fill: robeShade, line: line)
        let hand = CGPath(ellipseIn: CGRect(x: 14.5, y: 73, width: 10, height: 8.5), transform: nil)
        fillAndStroke(c, hand, fill: skin, line: line)
    }

    private static func drawHead(_ c: CGContext, line: CGFloat) {
        // Ears first, under the head.
        for x in [27.0, 66.0] {
            fillAndStroke(c, CGPath(ellipseIn: CGRect(x: x, y: 36, width: 7, height: 11), transform: nil), fill: skinShade, line: line)
        }
        let head = CGPath(ellipseIn: CGRect(x: 30, y: 14, width: 40, height: 46), transform: nil)
        fillAndStroke(c, head, fill: skin, line: line)
        // Shine on the dome.
        c.setFillColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.88, alpha: 0.55))
        c.fillEllipse(in: CGRect(x: 40, y: 18, width: 10, height: 5))
        // White tufts over the ears.
        for (x, flip) in [(31.0, 1.0), (69.0, -1.0)] {
            let tuft = CGMutablePath()
            tuft.move(to: CGPoint(x: x, y: 29))
            tuft.addCurve(to: CGPoint(x: x - 7 * flip, y: 33), control1: CGPoint(x: x - 3 * flip, y: 27), control2: CGPoint(x: x - 7 * flip, y: 29))
            tuft.addCurve(to: CGPoint(x: x - 8 * flip, y: 41), control1: CGPoint(x: x - 10 * flip, y: 36), control2: CGPoint(x: x - 10 * flip, y: 39))
            tuft.addCurve(to: CGPoint(x: x - 4 * flip, y: 47), control1: CGPoint(x: x - 9 * flip, y: 45), control2: CGPoint(x: x - 7 * flip, y: 47))
            tuft.addCurve(to: CGPoint(x: x + 1 * flip, y: 44), control1: CGPoint(x: x - 2 * flip, y: 47), control2: CGPoint(x: x, y: 46))
            tuft.closeSubpath()
            fillAndStroke(c, tuft, fill: beard, line: line)
        }
    }

    private static func drawBeard(_ c: CGContext, line: CGFloat, detailed: Bool) {
        let beardPath = CGMutablePath()
        beardPath.move(to: CGPoint(x: 31, y: 44))
        beardPath.addCurve(to: CGPoint(x: 34, y: 76), control1: CGPoint(x: 28, y: 56), control2: CGPoint(x: 29, y: 68))
        // A wavy end, the beard of someone who never owned a comb.
        beardPath.addCurve(to: CGPoint(x: 42, y: 90), control1: CGPoint(x: 36, y: 84), control2: CGPoint(x: 38, y: 88))
        beardPath.addCurve(to: CGPoint(x: 47, y: 87), control1: CGPoint(x: 44, y: 91), control2: CGPoint(x: 46, y: 89))
        beardPath.addCurve(to: CGPoint(x: 51, y: 96), control1: CGPoint(x: 47, y: 92), control2: CGPoint(x: 49, y: 95))
        beardPath.addCurve(to: CGPoint(x: 55, y: 87), control1: CGPoint(x: 54, y: 94), control2: CGPoint(x: 55, y: 90))
        beardPath.addCurve(to: CGPoint(x: 60, y: 89), control1: CGPoint(x: 56, y: 89), control2: CGPoint(x: 58, y: 90))
        beardPath.addCurve(to: CGPoint(x: 67, y: 74), control1: CGPoint(x: 64, y: 86), control2: CGPoint(x: 66, y: 80))
        beardPath.addCurve(to: CGPoint(x: 69, y: 44), control1: CGPoint(x: 71, y: 66), control2: CGPoint(x: 72, y: 56))
        // Up under the cheeks and round the mouth.
        beardPath.addCurve(to: CGPoint(x: 50, y: 57), control1: CGPoint(x: 66, y: 52), control2: CGPoint(x: 58, y: 57))
        beardPath.addCurve(to: CGPoint(x: 31, y: 44), control1: CGPoint(x: 42, y: 57), control2: CGPoint(x: 34, y: 52))
        beardPath.closeSubpath()

        c.saveGState()
        c.addPath(beardPath)
        c.clip()
        let colors = [beard, beardShade] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0.35, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 96), options: [])
        }
        c.restoreGState()
        c.addPath(beardPath)
        c.setStrokeColor(ink)
        c.setLineWidth(line)
        c.strokePath()

        if detailed {
            // A few strands.
            c.setStrokeColor(beardShade)
            c.setLineWidth(1.1)
            for (start, control, end) in [
                (CGPoint(x: 41, y: 64), CGPoint(x: 40, y: 72), CGPoint(x: 43, y: 81)),
                (CGPoint(x: 51, y: 66), CGPoint(x: 50, y: 76), CGPoint(x: 51, y: 86)),
                (CGPoint(x: 60, y: 64), CGPoint(x: 61, y: 71), CGPoint(x: 58, y: 80)),
            ] {
                c.move(to: start)
                c.addQuadCurve(to: end, control: control)
                c.strokePath()
            }
        }
    }

    private static func drawFace(_ c: CGContext, expression: DyogeneExpression, line: CGFloat, detailed: Bool) {
        // Cheeks warmed by the lantern.
        if detailed {
            c.setFillColor(amber.copy(alpha: 0.28)!)
            c.fillEllipse(in: CGRect(x: 34, y: 42, width: 8, height: 5))
            c.fillEllipse(in: CGRect(x: 58, y: 42, width: 8, height: 5))
        }

        // Eyes.
        c.setStrokeColor(ink)
        c.setFillColor(ink)
        let eyeY: CGFloat = 38
        let left = CGPoint(x: 41.5, y: eyeY)
        let right = CGPoint(x: 58.5, y: eyeY)
        switch expression {
        case .pleased:
            c.setLineWidth(line)
            for eye in [left, right] {
                c.move(to: CGPoint(x: eye.x - 3, y: eye.y + 0.8))
                c.addQuadCurve(to: CGPoint(x: eye.x + 3, y: eye.y + 0.8), control: CGPoint(x: eye.x, y: eye.y - 2.6))
                c.strokePath()
            }
        case .calm, .curious, .searching:
            let shift: CGFloat = expression == .searching ? -1.4 : 0
            let leftSize: CGFloat = expression == .curious ? 4.6 : 3.6
            c.fillEllipse(in: CGRect(x: left.x - leftSize / 2 + shift, y: eyeY - leftSize / 2, width: leftSize, height: leftSize + 0.4))
            c.fillEllipse(in: CGRect(x: right.x - 1.8 + shift, y: eyeY - 1.8, width: 3.6, height: 4))
            if detailed {
                // Catchlights from the lantern, on its side.
                c.setFillColor(flame)
                c.fillEllipse(in: CGRect(x: left.x - 1.3 + shift, y: eyeY - 1.4, width: 1.2, height: 1.2))
                c.fillEllipse(in: CGRect(x: right.x - 1.3 + shift, y: eyeY - 1.4, width: 1.2, height: 1.2))
                // Smile lines.
                c.setStrokeColor(skinShade)
                c.setLineWidth(1)
                c.move(to: CGPoint(x: 34.5, y: 37))
                c.addQuadCurve(to: CGPoint(x: 35.5, y: 42), control: CGPoint(x: 33.5, y: 40))
                c.move(to: CGPoint(x: 65.5, y: 37))
                c.addQuadCurve(to: CGPoint(x: 64.5, y: 42), control: CGPoint(x: 66.5, y: 40))
                c.strokePath()
            }
        }

        // Bushy brows. The left one always sits a little higher; curious lifts it further.
        let lift: CGFloat = switch expression {
        case .curious: 5
        case .pleased: 1.5
        case .calm, .searching: 2.5
        }
        for (start, end, raise) in [(CGPoint(x: 35, y: 33), CGPoint(x: 46, y: 32), lift), (CGPoint(x: 54, y: 32), CGPoint(x: 65, y: 33), 0)] {
            let brow = CGMutablePath()
            let top = min(start.y, end.y) - raise - 5.2
            brow.move(to: CGPoint(x: start.x, y: start.y - raise * 0.6))
            brow.addCurve(to: CGPoint(x: end.x, y: end.y - raise * 0.6),
                          control1: CGPoint(x: start.x + 2, y: top), control2: CGPoint(x: end.x - 2, y: top))
            brow.addCurve(to: CGPoint(x: start.x, y: start.y - raise * 0.6),
                          control1: CGPoint(x: end.x - 3, y: top + 4.4), control2: CGPoint(x: start.x + 3, y: top + 4.4))
            brow.closeSubpath()
            fillAndStroke(c, brow, fill: beard, line: line * 0.7)
        }

        // A generous nose.
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 48.3, y: 41.5))
        nose.addCurve(to: CGPoint(x: 45, y: 48), control1: CGPoint(x: 47.8, y: 44), control2: CGPoint(x: 44.5, y: 45.5))
        nose.addCurve(to: CGPoint(x: 55, y: 48), control1: CGPoint(x: 47, y: 51.5), control2: CGPoint(x: 53, y: 51.5))
        nose.addCurve(to: CGPoint(x: 51.7, y: 41.5), control1: CGPoint(x: 55.5, y: 45.5), control2: CGPoint(x: 52.2, y: 44))
        fillAndStroke(c, nose, fill: skinShade, line: line * 0.8)

        // Moustache, two soft curls.
        for flip in [1.0, -1.0] as [CGFloat] {
            let curl = CGMutablePath()
            curl.move(to: CGPoint(x: 50, y: 50.5))
            curl.addCurve(to: CGPoint(x: 50 - 13 * flip, y: 54), control1: CGPoint(x: 46 - 2 * flip, y: 49 + 0 * flip), control2: CGPoint(x: 50 - 10 * flip, y: 50))
            curl.addCurve(to: CGPoint(x: 50 - 9 * flip, y: 56.5), control1: CGPoint(x: 50 - 15 * flip, y: 56), control2: CGPoint(x: 50 - 12 * flip, y: 57.5))
            curl.addCurve(to: CGPoint(x: 50, y: 54.5), control1: CGPoint(x: 50 - 6 * flip, y: 55.5), control2: CGPoint(x: 50 - 3 * flip, y: 54.5))
            curl.closeSubpath()
            fillAndStroke(c, curl, fill: beard, line: line * 0.8)
        }
        // The smile under it.
        c.setStrokeColor(ink)
        c.setLineWidth(line * 0.8)
        c.move(to: CGPoint(x: 46.5, y: 58))
        c.addQuadCurve(to: CGPoint(x: 53.5, y: 58), control: CGPoint(x: 50, y: expression == .pleased ? 61.5 : 60))
        c.strokePath()
    }

    private static func drawLantern(_ c: CGContext, line: CGFloat, detailed: Bool) {
        // Handle.
        c.setStrokeColor(ink)
        c.setLineWidth(line)
        c.move(to: CGPoint(x: 14.5, y: 53))
        c.addCurve(to: CGPoint(x: 24.5, y: 53), control1: CGPoint(x: 15, y: 45), control2: CGPoint(x: 24, y: 45))
        c.strokePath()
        // Cap and base.
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: 12.5, y: 57))
        cap.addLine(to: CGPoint(x: 15.5, y: 52))
        cap.addLine(to: CGPoint(x: 23.5, y: 52))
        cap.addLine(to: CGPoint(x: 26.5, y: 57))
        cap.closeSubpath()
        fillAndStroke(c, cap, fill: lanternMetal, line: line)
        // Glass, lit.
        let glass = CGPath(roundedRect: CGRect(x: 13.5, y: 57, width: 12, height: 14), cornerWidth: 2, cornerHeight: 2, transform: nil)
        c.saveGState()
        c.addPath(glass)
        c.clip()
        let colors = [flame, amber] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0.2, 1]) {
            c.drawRadialGradient(gradient, startCenter: CGPoint(x: 19.5, y: 65), startRadius: 0,
                                 endCenter: CGPoint(x: 19.5, y: 65), endRadius: 9, options: [.drawsAfterEndLocation])
        }
        if detailed {
            // The flame.
            let flamePath = CGMutablePath()
            flamePath.move(to: CGPoint(x: 19.5, y: 60))
            flamePath.addCurve(to: CGPoint(x: 19.5, y: 68), control1: CGPoint(x: 23, y: 64), control2: CGPoint(x: 22, y: 68))
            flamePath.addCurve(to: CGPoint(x: 19.5, y: 60), control1: CGPoint(x: 17, y: 68), control2: CGPoint(x: 16, y: 64))
            c.addPath(flamePath)
            c.setFillColor(CGColor(srgbRed: 1, green: 0.98, blue: 0.9, alpha: 1))
            c.fillPath()
        }
        c.restoreGState()
        c.addPath(glass)
        c.setStrokeColor(ink)
        c.setLineWidth(line)
        c.strokePath()
        if detailed {
            // Cage bars.
            c.setLineWidth(line * 0.6)
            c.move(to: CGPoint(x: 17.5, y: 57))
            c.addLine(to: CGPoint(x: 17.5, y: 71))
            c.move(to: CGPoint(x: 21.5, y: 57))
            c.addLine(to: CGPoint(x: 21.5, y: 71))
            c.strokePath()
        }
        let base = CGPath(roundedRect: CGRect(x: 12.5, y: 70.5, width: 14, height: 4), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
        fillAndStroke(c, base, fill: lanternMetal, line: line)
    }
}
