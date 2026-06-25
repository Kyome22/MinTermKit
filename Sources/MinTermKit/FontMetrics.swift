import AppKit
import CoreText

/// Fixed cell geometry (width/height, fonts, baseline) derived from a monospaced
/// font, used by the renderer to lay text out on a fixed grid.
@MainActor
struct FontMetrics {
    let font: NSFont
    let boldFont: NSFont
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let ascent: CGFloat

    init(font: NSFont) {
        self.font = font
        self.boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)

        let ctFont = font as CTFont
        let fontAscent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)

        self.ascent = fontAscent
        self.cellHeight = ceil(fontAscent + descent + leading)
        // Use a representative glyph's advance rather than the font's maximum
        // advance, which can be wider than real characters and loosen the grid.
        self.cellWidth = Self.advance(of: "0", in: ctFont)
    }

    private static func advance(of character: Character, in font: CTFont) -> CGFloat {
        let utf16 = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let width = advances.reduce(0) { $0 + $1.width }
        return (width).rounded()
    }
}
