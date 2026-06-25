import SwiftUI

/// The colors ``TerminalView`` uses for the screen background, default text,
/// cursor, and selection highlight.
///
/// The ANSI 16/256-color palette for colored output comes from the engine; this
/// theme only controls the surrounding/default colors of the view.
public struct TerminalTheme: Sendable {
    /// The screen background, and the fill color for cells with a default background.
    public var background: Color
    /// The text color for cells with a default foreground.
    public var foreground: Color
    /// The cursor block color.
    public var cursor: Color
    /// The selection highlight color.
    public var selection: Color

    /// Creates a theme. Defaults to a classic dark terminal (black on white).
    public init(
        background: Color = .black,
        foreground: Color = .white,
        cursor: Color = Color(white: 0.85),
        selection: Color = Color(nsColor: .selectedContentBackgroundColor)
    ) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
    }

    /// The default dark theme: black background, white text.
    public static let `default` = TerminalTheme()
}
