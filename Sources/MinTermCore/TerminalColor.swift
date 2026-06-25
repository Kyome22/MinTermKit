/// A color used for a cell's foreground or background.
public enum TerminalColor: Equatable, Sendable {
    /// The terminal's configured default foreground/background.
    case defaultColor
    /// A palette index in the 0..<256 ANSI/256-color space.
    case ansi(UInt8)
    /// A 24-bit true color value.
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

/// The default xterm-compatible 256-color palette, expressed as RGB triples.
public enum Palette {
    /// The 16 standard ANSI colors (0–7 normal, 8–15 bright), as RGB triples.
    static let base16: [(red: UInt8, green: UInt8, blue: UInt8)] = [
        (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
        (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
        (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
        (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    ]

    /// Returns the RGB triple for a 256-color palette index.
    ///
    /// Covers the 16 base colors (0–15), the 6×6×6 color cube (16–231), and the
    /// grayscale ramp (232–255).
    ///
    /// - Parameter index: A palette index in the range `0..<256`.
    /// - Returns: The corresponding red/green/blue components.
    public static func rgb(forAnsi index: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        if index < 16 {
            return base16[index]
        }
        if index < 232 {
            let value = index - 16
            let red = value / 36
            let green = (value / 6) % 6
            let blue = value % 6
            func channel(_ level: Int) -> UInt8 {
                level == 0 ? 0 : UInt8(55 + level * 40)
            }
            return (channel(red), channel(green), channel(blue))
        }
        let gray = UInt8(8 + (index - 232) * 10)
        return (gray, gray, gray)
    }
}
