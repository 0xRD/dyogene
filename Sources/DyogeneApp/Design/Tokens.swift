import AppKit
import DyogeneCore
import SwiftUI

// Design tokens of Dyogène. See docs/DESIGN.md.
//
// The idea: Diogenes' jar at night. A deep indigo night (not black), one warm accent (the
// lantern's amber), and the content of the jar going from fresh teal to dusty sand.

enum Palette {
    // Fixed brand colours.
    static let night = NSColor(hex: 0x1C2140)
    static let lantern = NSColor(hex: 0xF2B33D)
    static let glow = NSColor(hex: 0xFFE6A8)
    static let patina = NSColor(hex: 0x4E8C84)
    static let dust = NSColor(hex: 0xB9AE9C)
    static let marble = NSColor(hex: 0xEEEAE3)

    // Surfaces, per appearance.
    static let canvas = NSColor.dynamic(light: 0xEEEAE3, dark: 0x1C2140)
    static let panel = NSColor.dynamic(light: 0xF7F4EE, dark: 0x232850)
    static let inset = NSColor.dynamic(light: 0xE4DFD6, dark: 0x161A34)
    static let stroke = NSColor.dynamic(light: 0x2B2A3A, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.08)
    static let ink = NSColor.dynamic(light: 0x1F2035, dark: 0xF1EDE4)
    static let inkSecondary = NSColor.dynamic(light: 0x5D5B6B, dark: 0xB5B2C4)
    /// The accent as text: amber is too light on marble, so it darkens in light mode.
    static let lanternInk = NSColor.dynamic(light: 0x8A5A00, dark: 0xF2B33D)
    static let danger = NSColor.dynamic(light: 0xA3362B, dark: 0xF08C7E)
    static let dangerFill = NSColor.dynamic(light: 0xB5402F, dark: 0xC2513F)

    // Dust ramp of the map, fresh to old.
    static let dustRamp: [NSColor] = [
        NSColor.dynamic(light: 0x7FBDB3, dark: 0x2F7069),
        NSColor.dynamic(light: 0xA9B9C2, dark: 0x45597A),
        NSColor.dynamic(light: 0xC9C0B4, dark: 0x6A6478),
        NSColor.dynamic(light: 0xD8C7A8, dark: 0x8D7C62),
    ]

    static func kind(_ kind: Kind) -> NSColor {
        switch kind {
        case .video: NSColor.dynamic(light: 0xD98E80, dark: 0xA4544A)
        case .photo: NSColor.dynamic(light: 0xE3B676, dark: 0xA97A33)
        case .audio: NSColor.dynamic(light: 0xB79AD0, dark: 0x7A5793)
        case .app: NSColor.dynamic(light: 0x8FB2E6, dark: 0x3F679F)
        case .archive: NSColor.dynamic(light: 0xD9C97E, dark: 0x93832F)
        case .virtualDisk: NSColor.dynamic(light: 0x9DA9C4, dark: 0x515E7F)
        case .developer: NSColor.dynamic(light: 0x82C2A8, dark: 0x2F7A62)
        case .cache: NSColor.dynamic(light: 0xB7BAC2, dark: 0x5E6270)
        case .document: NSColor.dynamic(light: 0xE6D9BC, dark: 0x8A7C5C)
        case .other: NSColor.dynamic(light: 0xC4C3CF, dark: 0x4A4D66)
        }
    }

    static let plain = NSColor.dynamic(light: 0xC9C6CF, dark: 0x3A3F63)

    /// Colour of the dust ramp at a level 0...1, resolved for the appearance it is drawn in.
    static func dust(_ level: Double) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved: NSColor = dustRamp[0]
            appearance.performAsCurrentDrawingAppearance {
                let ramp = dustRamp.map { $0.usingColorSpace(.sRGB) ?? $0 }
                let position = max(0, min(1, level)) * Double(ramp.count - 1)
                let low = Int(position.rounded(.down))
                let high = min(ramp.count - 1, low + 1)
                resolved = ramp[low].blended(withFraction: position - Double(low), of: ramp[high]) ?? ramp[low]
            }
            return resolved
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        }
    }

    /// Relative luminance, to pick a readable ink on a fill.
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0.5 }
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension Color {
    static let canvas = Color(nsColor: Palette.canvas)
    static let panel = Color(nsColor: Palette.panel)
    static let inset = Color(nsColor: Palette.inset)
    static let stroke = Color(nsColor: Palette.stroke)
    static let ink = Color(nsColor: Palette.ink)
    static let inkSecondary = Color(nsColor: Palette.inkSecondary)
    static let lantern = Color(nsColor: Palette.lantern)
    static let lanternInk = Color(nsColor: Palette.lanternInk)
    static let glow = Color(nsColor: Palette.glow)
    static let night = Color(nsColor: Palette.night)
    static let danger = Color(nsColor: Palette.danger)
    static let dangerFill = Color(nsColor: Palette.dangerFill)
}

enum Typeface {
    /// New York, for titles and big figures.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// SF Pro with figures that line up.
    static func data(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static func nsDisplay(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: serif, size: size) ?? base
    }

    static func nsData(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

enum Metrics {
    static let inspectorWidth: CGFloat = 300
    static let corner: CGFloat = 10
    static let tileCorner: CGFloat = 4
}
