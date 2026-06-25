/// Computes the terminal display width of a Unicode scalar.
///
/// Returns 0 for combining/zero-width marks, 2 for wide (East Asian / emoji)
/// scalars, and 1 otherwise. This is a compact approximation of `wcwidth`
/// sufficient for the common cases a terminal needs to lay out correctly.
public enum UnicodeWidth {
    /// Returns the number of terminal cells the scalar occupies.
    ///
    /// - Parameter scalar: The Unicode scalar to measure.
    /// - Returns: `0` for combining/zero-width marks, `2` for wide scalars, `1` otherwise.
    public static func of(_ scalar: Unicode.Scalar) -> Int {
        let value = scalar.value

        if value == 0 {
            return 0
        }
        if isZeroWidth(value) {
            return 0
        }
        if isWide(value) {
            return 2
        }
        return 1
    }

    private static func isZeroWidth(_ value: UInt32) -> Bool {
        for range in zeroWidthRanges where range.contains(value) {
            return true
        }
        return false
    }

    private static func isWide(_ value: UInt32) -> Bool {
        for range in wideRanges where range.contains(value) {
            return true
        }
        return false
    }

    private static let zeroWidthRanges: [ClosedRange<UInt32>] = [
        0x0300...0x036F,   // Combining Diacritical Marks
        0x0483...0x0489,
        0x0591...0x05BD,
        0x0610...0x061A,
        0x064B...0x065F,
        0x0670...0x0670,
        0x06D6...0x06DC,
        0x200B...0x200F,   // Zero-width space / direction marks
        0x20D0...0x20FF,   // Combining marks for symbols
        0x3099...0x309A,   // Combining katakana-hiragana voiced/semi-voiced marks (NFD dakuten)
        0xFE00...0xFE0F,   // Variation selectors
        0xFE20...0xFE2F,
    ]

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,   // Hangul Jamo
        0x2329...0x232A,
        0x2E80...0x303E,   // CJK radicals, Kangxi
        0x3041...0x33FF,   // Hiragana, Katakana, CJK symbols
        0x3400...0x4DBF,   // CJK Extension A
        0x4E00...0x9FFF,   // CJK Unified Ideographs
        0xA000...0xA4CF,   // Yi
        0xAC00...0xD7A3,   // Hangul Syllables
        0xF900...0xFAFF,   // CJK Compatibility Ideographs
        0xFE10...0xFE19,   // Vertical forms
        0xFE30...0xFE6F,   // CJK Compatibility forms
        0xFF00...0xFF60,   // Fullwidth forms
        0xFFE0...0xFFE6,
        0x1F300...0x1F64F, // Emoji (Misc symbols & pictographs, emoticons)
        0x1F900...0x1F9FF, // Supplemental symbols and pictographs
        0x20000...0x3FFFD, // CJK Extension B and beyond
    ]
}
