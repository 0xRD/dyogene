// Draws the Dyogène icon: Diogenes' jar, its body a treemap of tiles from fresh teal to dusty sand,
// with lantern light rising from its mouth. Usage: swift scripts/render-icon.swift OUT.png [SIZE]
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "icon-1024.png"
let size = arguments.count > 2 ? Int(arguments[2]) ?? 1024 : 1024
let s = CGFloat(size) / 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Work top-down in a 1024 grid.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: s, y: -s)

// Plate: macOS icon grid, 824 pt rounded square.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
context.addPath(platePath)
context.setFillColor(rgb(0x1C2140))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(platePath)
context.clip()
let night = CGGradient(colorsSpace: space, colors: [rgb(0x2A3163), rgb(0x1C2140), rgb(0x121530)] as CFArray,
                       locations: [0, 0.55, 1])!
context.drawLinearGradient(night, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// Lantern light rising from the jar's mouth.
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFE6A8, 0.95), rgb(0xF2B33D, 0.45), rgb(0xF2B33D, 0)] as CFArray,
                      locations: [0, 0.35, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 318), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 300), endRadius: 330, options: [])

// Dust motes in the light.
let motes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (430, 210, 7, 0.75), (590, 180, 5, 0.6), (515, 150, 4, 0.5), (640, 240, 6, 0.55), (380, 255, 4, 0.45),
    (470, 120, 3, 0.35), (560, 235, 3, 0.7), (612, 135, 3, 0.4),
]
for (x, y, r, a) in motes {
    context.setFillColor(rgb(0xFFF1CC, a))
    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// The jar (a pithos): rim, short neck, round shoulders, narrow foot.
let jar = CGMutablePath()
jar.move(to: CGPoint(x: 392, y: 318))
jar.addLine(to: CGPoint(x: 632, y: 318))
jar.addCurve(to: CGPoint(x: 612, y: 372), control1: CGPoint(x: 636, y: 340), control2: CGPoint(x: 612, y: 350))
jar.addCurve(to: CGPoint(x: 790, y: 560), control1: CGPoint(x: 700, y: 395), control2: CGPoint(x: 790, y: 455))
jar.addCurve(to: CGPoint(x: 600, y: 846), control1: CGPoint(x: 790, y: 700), control2: CGPoint(x: 700, y: 800))
jar.addLine(to: CGPoint(x: 424, y: 846))
jar.addCurve(to: CGPoint(x: 234, y: 560), control1: CGPoint(x: 324, y: 800), control2: CGPoint(x: 234, y: 700))
jar.addCurve(to: CGPoint(x: 412, y: 372), control1: CGPoint(x: 234, y: 455), control2: CGPoint(x: 324, y: 395))
jar.addCurve(to: CGPoint(x: 392, y: 318), control1: CGPoint(x: 412, y: 350), control2: CGPoint(x: 388, y: 340))
jar.closeSubpath()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: rgb(0x05060F, 0.55))
context.addPath(jar)
context.setFillColor(rgb(0x14182F))
context.fillPath()
context.restoreGState()

// Treemap tiles inside the jar, fresh at the top, dusty at the bottom.
context.saveGState()
context.addPath(jar)
context.clip()
let fresh = (r: 0x3B, g: 0x86, b: 0x7C)
let dusty = (r: 0xA8, g: 0x9B, b: 0x84)
func tile(_ t: CGFloat) -> CGColor {
    let mix = { (a: Int, b: Int) -> CGFloat in (CGFloat(a) * (1 - t) + CGFloat(b) * t) / 255 }
    return CGColor(srgbRed: mix(fresh.r, dusty.r), green: mix(fresh.g, dusty.g), blue: mix(fresh.b, dusty.b), alpha: 1)
}
// Hand-placed squarified layout (x, y, w, h, dust).
let tiles: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (220, 300, 330, 250, 0.05), (550, 300, 260, 150, 0.2), (550, 450, 130, 100, 0.3), (680, 450, 130, 100, 0.45),
    (220, 550, 200, 300, 0.85), (420, 550, 230, 170, 0.6), (650, 550, 160, 170, 0.7),
    (420, 720, 130, 130, 0.95), (550, 720, 140, 130, 0.8), (690, 720, 120, 130, 1.0),
]
for (x, y, w, h, d) in tiles {
    let rect = CGRect(x: x + 5, y: y + 5, width: w - 10, height: h - 10)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.setFillColor(tile(d))
    context.fillPath()
    // Cushion: light from the mouth above.
    let shade = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0), rgb(0x000000, 0.18)] as CFArray,
                           locations: [0, 0.45, 1])!
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.clip()
    context.drawLinearGradient(shade, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    context.restoreGState()
}
// Lantern light falling onto the top of the jar.
let spill = CGGradient(colorsSpace: space, colors: [rgb(0xFFD77A, 0.55), rgb(0xF2B33D, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(spill, startCenter: CGPoint(x: 512, y: 330), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 330), endRadius: 300, options: [])
context.restoreGState()

// Outline and foot.
context.addPath(jar)
context.setStrokeColor(rgb(0x0C0F22))
context.setLineWidth(12)
context.strokePath()
let foot = CGRect(x: 432, y: 840, width: 160, height: 34)
context.addPath(CGPath(roundedRect: foot, cornerWidth: 12, cornerHeight: 12, transform: nil))
context.setFillColor(rgb(0x0C0F22))
context.fillPath()

// Rim: the warm edge of the jar's mouth.
let rim = CGRect(x: 380, y: 300, width: 264, height: 40)
context.addPath(CGPath(roundedRect: rim, cornerWidth: 20, cornerHeight: 20, transform: nil))
context.setFillColor(rgb(0xF2B33D))
context.fillPath()
context.addPath(CGPath(roundedRect: rim.insetBy(dx: 16, dy: 12), cornerWidth: 8, cornerHeight: 8, transform: nil))
context.setFillColor(rgb(0xFFE6A8))
context.fillPath()

context.restoreGState()

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("render-icon: wrote \(output)")
