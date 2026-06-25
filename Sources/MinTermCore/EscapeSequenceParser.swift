/// Receives the decoded events produced by `EscapeSequenceParser`.
@MainActor
protocol ParserHandler: AnyObject {
    func parserPrint(_ scalar: Unicode.Scalar)
    func parserExecute(_ control: UInt8)
    func parserCSIDispatch(final: UInt8, params: [Int], prefix: UInt8, intermediates: [UInt8])
    func parserOSCDispatch(_ data: [UInt8])
    func parserESCDispatch(final: UInt8, intermediates: [UInt8])
}

/// Incremental UTF-8 decoder that preserves state across feed boundaries.
struct UTF8Decoder {
    private var codepoint = UInt32.zero
    private var remaining = 0

    mutating func reset() {
        codepoint = 0
        remaining = 0
    }

    mutating func feed(_ byte: UInt8, emit: (Unicode.Scalar) -> Void) {
        if remaining == 0 {
            if byte < 0x80 {
                emit(Unicode.Scalar(byte))
            } else if byte & 0xE0 == 0xC0 {
                codepoint = UInt32(byte & 0x1F)
                remaining = 1
            } else if byte & 0xF0 == 0xE0 {
                codepoint = UInt32(byte & 0x0F)
                remaining = 2
            } else if byte & 0xF8 == 0xF0 {
                codepoint = UInt32(byte & 0x07)
                remaining = 3
            } else {
                emit(Unicode.Scalar(0xFFFD)!)
            }
        } else {
            if byte & 0xC0 == 0x80 {
                codepoint = (codepoint << 6) | UInt32(byte & 0x3F)
                remaining -= 1
                if remaining == 0 {
                    emit(Unicode.Scalar(codepoint) ?? Unicode.Scalar(0xFFFD)!)
                    codepoint = 0
                }
            } else {
                // Invalid continuation: abandon and reprocess this byte fresh.
                remaining = 0
                codepoint = 0
                feed(byte, emit: emit)
            }
        }
    }
}

/// A compact VT500-style escape-sequence parser. It walks a small state machine
/// and forwards print/execute/CSI/OSC/ESC events to its handler.
@MainActor
final class EscapeSequenceParser {
    private enum State {
        case ground
        case escape
        case escapeIntermediate
        case csi
        case osc
        case oscEscape
        case stringIgnore       // DCS/APC/PM/SOS payloads we don't interpret
        case stringIgnoreEscape
    }

    private var state: State = .ground
    private var params: [Int] = []
    private var currentParam = 0
    private var hasParam = false
    private var prefix = UInt8.zero
    private var intermediates: [UInt8] = []
    private var oscBuffer: [UInt8] = []
    private var decoder = UTF8Decoder()

    func parse(_ bytes: ArraySlice<UInt8>, handler: any ParserHandler) {
        for byte in bytes {
            consume(byte, handler: handler)
        }
    }

    private func consume(_ byte: UInt8, handler: any ParserHandler) {
        switch state {
        case .ground:
            if byte == 0x1B {
                state = .escape
            } else if byte < 0x20 || byte == 0x7F {
                decoder.reset()
                handler.parserExecute(byte)
            } else {
                decoder.feed(byte) { handler.parserPrint($0) }
            }

        case .escape:
            handleEscape(byte, handler: handler)

        case .escapeIntermediate:
            // We only reach here for charset designators; swallow the id byte.
            state = .ground

        case .csi:
            handleCSI(byte, handler: handler)

        case .osc:
            if byte == 0x07 {
                handler.parserOSCDispatch(oscBuffer)
                state = .ground
            } else if byte == 0x1B {
                state = .oscEscape
            } else {
                oscBuffer.append(byte)
            }

        case .oscEscape:
            handler.parserOSCDispatch(oscBuffer)
            state = .ground
            if byte != 0x5C {
                consume(byte, handler: handler)
            }

        case .stringIgnore:
            if byte == 0x07 {
                state = .ground
            } else if byte == 0x1B {
                state = .stringIgnoreEscape
            }

        case .stringIgnoreEscape:
            state = .ground
            if byte != 0x5C {
                consume(byte, handler: handler)
            }
        }
    }

    private func handleEscape(_ byte: UInt8, handler: any ParserHandler) {
        switch byte {
        case 0x5B: // [
            beginCSI()
        case 0x5D: // ]
            oscBuffer = []
            state = .osc
        case 0x50, 0x58, 0x5E, 0x5F: // P (DCS), X (SOS), ^ (PM), _ (APC)
            state = .stringIgnore
        case 0x28, 0x29, 0x2A, 0x2B: // charset designators ( ) * +
            state = .escapeIntermediate
        default:
            if byte >= 0x30 {
                handler.parserESCDispatch(final: byte, intermediates: [])
            }
            state = .ground
        }
    }

    private func beginCSI() {
        params = []
        currentParam = 0
        hasParam = false
        prefix = 0
        intermediates = []
        state = .csi
    }

    private func handleCSI(_ byte: UInt8, handler: any ParserHandler) {
        switch byte {
        case 0x30...0x39: // digit
            currentParam = currentParam * 10 + Int(byte - 0x30)
            hasParam = true
        case 0x3B: // ;
            params.append(hasParam ? currentParam : 0)
            currentParam = 0
            hasParam = false
        case 0x3C...0x3F: // private prefix ? < = >
            prefix = byte
        case 0x20...0x2F: // intermediate
            intermediates.append(byte)
        case 0x40...0x7E: // final byte
            params.append(hasParam ? currentParam : 0)
            handler.parserCSIDispatch(
                final: byte,
                params: params,
                prefix: prefix,
                intermediates: intermediates
            )
            state = .ground
        default:
            if byte < 0x20 {
                handler.parserExecute(byte)
            } else {
                state = .ground
            }
        }
    }
}
