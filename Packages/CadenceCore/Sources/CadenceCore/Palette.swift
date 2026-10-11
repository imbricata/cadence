import SwiftUI

/// A curated set of ~10 muted, tasteful colors that read well in both light and dark mode.
public enum AreaPalette {
    public static let all: [String] = [
        "#C46A5A", // cedar
        "#D9975B", // apricot
        "#C9A227", // honey
        "#7A9C6A", // sage
        "#5C9B96", // teal
        "#6A93B8", // sky
        "#7A7FB0", // indigo
        "#9C82B0", // lilac
        "#B57492", // rose
        "#888C96"  // slate
    ]

    public static var nextUnused: [String] {
        all
    }
}

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}