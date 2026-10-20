import SwiftUI
import CadenceCore

/// An Area's colour with light and dark variants. `Area.colorHex` stays the stored value (so existing data
/// maps), and the dark variant is derived: slightly lighter and a touch less saturated.
struct AreaColor: Equatable {
    let hex: String

    init(_ hex: String) { self.hex = hex }

    static let classes = AreaColor("#888C96")

    private var rgb: (r: Double, g: Double, b: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    private var darkRGB: (r: Double, g: Double, b: Double) {
        let (r, g, b) = rgb
        var (h, s, v) = Self.toHSB(r, g, b)
        s *= 0.88
        v = min(1, v * 1.12 + 0.04)
        return Self.fromHSB(h, s, v)
    }

    /// Solid colour for dots, bars and glyphs.
    var base: Color {
        Color(light: Color(red: rgb.r, green: rgb.g, blue: rgb.b), dark: Color(red: darkRGB.r, green: darkRGB.g, blue: darkRGB.b))
    }

    /// Translucent tint for block backgrounds. Body text on top stays `.primary` in both appearances.
    var fill: Color {
        Color(
            light: Color(red: rgb.r, green: rgb.g, blue: rgb.b).opacity(0.16),
            dark: Color(red: darkRGB.r, green: darkRGB.g, blue: darkRGB.b).opacity(0.26)
        )
    }

    var stroke: Color {
        Color(
            light: Color(red: rgb.r, green: rgb.g, blue: rgb.b).opacity(0.55),
            dark: Color(red: darkRGB.r, green: darkRGB.g, blue: darkRGB.b).opacity(0.65)
        )
    }

    /// Text/glyph colour to draw on top of `fill`.
    var onFill: Color { .primary }

    // MARK: HSB helpers

    private static func toHSB(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    private static func fromHSB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h * 6) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

extension Area {
    var color: AreaColor { isClassesCalendar ? .classes : AreaColor(colorHex) }
}

extension Color {
    /// A colour that changes with the appearance.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #endif
    }
}
