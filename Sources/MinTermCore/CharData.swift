/// Visual style flags applied to a cell.
public struct CharacterStyle: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Renders the glyph using the bold font variant.
    public static let bold = CharacterStyle(rawValue: 1 << 0)
    /// Draws an underline beneath the cell.
    public static let underline = CharacterStyle(rawValue: 1 << 1)
    /// Swaps the foreground and background colors.
    public static let inverse = CharacterStyle(rawValue: 1 << 2)
}

/// The color/style attributes that apply to a single cell.
public struct Attribute: Equatable, Sendable {
    /// The foreground (text) color.
    public var foreground: TerminalColor
    /// The background (fill) color.
    public var background: TerminalColor
    /// The bold/underline/inverse style flags.
    public var style: CharacterStyle

    /// Creates an attribute from the given colors and style flags.
    public init(
        foreground: TerminalColor = .defaultColor,
        background: TerminalColor = .defaultColor,
        style: CharacterStyle = []
    ) {
        self.foreground = foreground
        self.background = background
        self.style = style
    }

    /// The default attribute: default colors and no style flags.
    public static let `default` = Attribute()
}

/// A single terminal grid cell: a base scalar (plus any combining marks),
/// its attributes, and its display width.
public struct CharData: Equatable, Sendable {
    /// The base Unicode scalar occupying the cell.
    public var scalar: Unicode.Scalar
    /// Zero-width combining marks attached to the base scalar (e.g. NFD dakuten).
    public var combining: [Unicode.Scalar]
    /// The color/style attributes of the cell.
    public var attribute: Attribute
    /// Display width in cells: 1 (normal), 2 (wide/CJK), or 0 (trailing half of a wide cell).
    public var width: Int8

    /// Creates a cell from a base scalar, attributes, width, and optional combining marks.
    public init(scalar: Unicode.Scalar, attribute: Attribute, width: Int8, combining: [Unicode.Scalar] = []) {
        self.scalar = scalar
        self.combining = combining
        self.attribute = attribute
        self.width = width
    }

    /// The full grapheme to render: the base scalar with any combining marks.
    public var displayText: String {
        if combining.isEmpty {
            return String(scalar)
        }
        var text = String(scalar)
        for mark in combining {
            text.unicodeScalars.append(mark)
        }
        return text
    }

    /// A blank, single-width cell with default attributes.
    public static let blank = CharData(scalar: " ", attribute: .default, width: 1)

    /// A blank cell that carries the given background (used for background-color erases).
    public static func blank(with attribute: Attribute) -> CharData {
        CharData(scalar: " ", attribute: attribute, width: 1)
    }
}
