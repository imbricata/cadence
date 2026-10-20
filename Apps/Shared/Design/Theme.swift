import SwiftUI

/// Spacing, radii and motion used everywhere, so screens line up without one-off numbers.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let block: CGFloat = 6
        static let card: CGFloat = 12
    }

    static let snappy = Animation.snappy(duration: 0.2)

    #if os(macOS)
    static let hourHeight: CGFloat = 52
    #else
    static let hourHeight: CGFloat = 56
    #endif
}

extension View {
    /// Wraps a state change in the app's single quick animation.
    func snappy<V: Equatable>(value: V) -> some View { animation(Theme.snappy, value: value) }
}
