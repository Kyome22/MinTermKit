/// A non-text key that maps to a fixed escape sequence.
public enum SpecialKey: Sendable, Equatable {
    /// Arrow keys.
    case up, down, right, left
    /// Home and End keys.
    case home, end
    /// Page Up and Page Down keys.
    case pageUp, pageDown
    /// Insert and forward-delete keys.
    case insert, delete
    /// Backspace, Return/Enter, Tab, and Escape keys.
    case backspace, enter, tab, escape
    /// A function key, where the associated value is the number (1 = F1 … 12 = F12).
    case function(Int)
}

/// Pure translation of keys/text into the byte sequences a terminal expects.
/// The view layer feeds raw key events in; the bytes go to the host program.
public enum KeyEncoder {
    /// Encodes a special key into its escape sequence.
    ///
    /// - Parameters:
    ///   - key: The key to encode.
    ///   - applicationCursor: When `true`, cursor keys use the DECCKM application
    ///     form (`ESC O A`) instead of the normal form (`ESC [ A`).
    /// - Returns: The bytes to send to the host program.
    public static func encode(_ key: SpecialKey, applicationCursor: Bool) -> [UInt8] {
        switch key {
        case .up: return cursor("A", applicationCursor)
        case .down: return cursor("B", applicationCursor)
        case .right: return cursor("C", applicationCursor)
        case .left: return cursor("D", applicationCursor)
        case .home: return cursor("H", applicationCursor)
        case .end: return cursor("F", applicationCursor)
        case .pageUp: return csi("5~")
        case .pageDown: return csi("6~")
        case .insert: return csi("2~")
        case .delete: return csi("3~")
        case .backspace: return [0x7F]
        case .enter: return [0x0D]
        case .tab: return [0x09]
        case .escape: return [0x1B]
        case .function(let n): return functionKey(n)
        }
    }

    /// Produces the control byte for Ctrl+<key>, e.g. Ctrl+A -> 0x01.
    ///
    /// - Parameter ascii: The ASCII value of the key combined with Control.
    /// - Returns: A single-byte sequence with the control code.
    public static func control(_ ascii: UInt8) -> [UInt8] {
        [ascii & 0x1F]
    }

    /// Normalizes pasted text (CRLF → CR) and optionally wraps it in bracketed-paste markers.
    ///
    /// - Parameters:
    ///   - text: The text to paste.
    ///   - bracketed: When `true`, surrounds the body with `ESC [ 200~` / `ESC [ 201~`.
    /// - Returns: The bytes to send to the host program.
    public static func paste(_ text: String, bracketed: Bool) -> [UInt8] {
        var body: [UInt8] = []
        var previous = UInt8.zero
        for byte in text.utf8 {
            if byte == 0x0A, previous == 0x0D {
                previous = byte
                continue // collapse CRLF into a single CR
            }
            body.append(byte == 0x0A ? 0x0D : byte)
            previous = byte
        }
        guard bracketed else { return body }
        return Array("\u{1b}[200~".utf8) + body + Array("\u{1b}[201~".utf8)
    }

    private static func cursor(_ final: Character, _ applicationCursor: Bool) -> [UInt8] {
        let introducer: [UInt8] = applicationCursor ? [0x1B, 0x4F] : [0x1B, 0x5B] // ESC O vs ESC [
        return introducer + Array(String(final).utf8)
    }

    private static func csi(_ tail: String) -> [UInt8] {
        [0x1B, 0x5B] + Array(tail.utf8)
    }

    private static func functionKey(_ number: Int) -> [UInt8] {
        switch number {
        case 1: return [0x1B, 0x4F, 0x50] // ESC O P
        case 2: return [0x1B, 0x4F, 0x51]
        case 3: return [0x1B, 0x4F, 0x52]
        case 4: return [0x1B, 0x4F, 0x53]
        case 5: return csi("15~")
        case 6: return csi("17~")
        case 7: return csi("18~")
        case 8: return csi("19~")
        case 9: return csi("20~")
        case 10: return csi("21~")
        case 11: return csi("23~")
        case 12: return csi("24~")
        default: return []
        }
    }
}
