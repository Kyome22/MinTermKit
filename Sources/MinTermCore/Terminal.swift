/// How mouse events should be reported to the host program.
public enum MouseMode: Sendable, Equatable {
    /// Mouse reporting is disabled.
    case off
    /// `?1000` — report press and release only.
    case normal
    /// `?1002` — report press, release, and drag motion.
    case buttonEvent
    /// `?1003` — report all motion.
    case anyEvent
}

/// How mouse coordinates are encoded on the wire.
public enum MouseEncoding: Sendable, Equatable {
    /// The legacy `CSI M` byte-offset encoding.
    case normal
    /// `?1006` — the SGR `CSI < … M/m` encoding.
    case sgr
}

/// A mouse action reported by the view layer.
public enum MouseAction: Sendable, Equatable {
    /// A button was pressed.
    case press
    /// A button was released.
    case release
    /// The pointer moved while a button was held.
    case drag
}

/// Receives state changes from the engine. The host (view/process) implements it.
@MainActor
public protocol TerminalDelegate: AnyObject {
    /// The engine wants to send bytes to the host program (key responses, mouse, DSR…).
    func terminalSend(_ terminal: Terminal, data: [UInt8])
    /// Screen content changed and should be redrawn.
    func terminalDidUpdate(_ terminal: Terminal)
    /// The terminal rang the bell (`BEL`).
    func terminalBell(_ terminal: Terminal)
    /// The host set the window/icon title (OSC 0/2).
    func terminalSetTitle(_ terminal: Terminal, title: String)
    /// The active buffer switched between the normal and alternate screens.
    func terminalBufferActivated(_ terminal: Terminal, usingAlt: Bool)
}

/// Default no-op implementations so conformers only override what they need.
public extension TerminalDelegate {
    func terminalDidUpdate(_ terminal: Terminal) {}
    func terminalBell(_ terminal: Terminal) {}
    func terminalSetTitle(_ terminal: Terminal, title: String) {}
    func terminalBufferActivated(_ terminal: Terminal, usingAlt: Bool) {}
}

/// A UI-agnostic VT100/xterm terminal emulator.
///
/// `Terminal` is the heart of the engine: it consumes bytes from the host
/// program via ``feed(_:)-(ArraySlice<UInt8>)``, drives a VT500-style escape
/// sequence parser to maintain the screen grid and scrollback, and exposes that
/// grid for rendering via ``displayLine(_:)`` and ``displayCursor``. It knows
/// nothing about UI or processes; all outside communication flows through its
/// ``delegate``.
@MainActor
public final class Terminal {
    /// Receives engine state changes (output bytes, redraw requests, title, …).
    public weak var delegate: (any TerminalDelegate)?

    /// The number of columns in the grid.
    public private(set) var cols: Int
    /// The number of rows in the grid.
    public private(set) var rows: Int

    private let normalBuffer: Buffer
    private let altBuffer: Buffer
    private var buffer: Buffer

    private var currentAttribute: Attribute = .default
    private let parser = EscapeSequenceParser()

    // Modes

    /// Whether application cursor keys (DECCKM) are active; affects key encoding.
    public private(set) var applicationCursorKeys = false
    /// Whether the cursor should be drawn (DECTCEM `?25`).
    public private(set) var cursorVisible = true
    /// Whether bracketed paste mode (`?2004`) is active.
    public private(set) var bracketedPasteEnabled = false
    /// The current mouse reporting mode requested by the host program.
    public private(set) var mouseMode: MouseMode = .off
    /// The current mouse coordinate encoding requested by the host program.
    public private(set) var mouseEncoding: MouseEncoding = .normal
    /// Whether the alternate screen buffer is currently active.
    public private(set) var usingAltBuffer = false
    private var autoWrap = true
    private var insertMode = false

    private var scrollbackOffset = 0

    /// Creates a terminal with the given grid size and scrollback capacity.
    ///
    /// - Parameters:
    ///   - cols: The initial number of columns.
    ///   - rows: The initial number of rows.
    ///   - scrollbackLimit: The maximum number of history lines to retain.
    public init(cols: Int = 80, rows: Int = 24, scrollbackLimit: Int = 1000) {
        self.cols = cols
        self.rows = rows
        normalBuffer = Buffer(cols: cols, rows: rows, allowsScrollback: true, scrollbackLimit: scrollbackLimit)
        altBuffer = Buffer(cols: cols, rows: rows, allowsScrollback: false, scrollbackLimit: 0)
        buffer = normalBuffer
    }

    // MARK: Input

    /// Feeds output bytes from the host program into the parser, updating the grid.
    ///
    /// - Parameter bytes: A slice of bytes received from the program (e.g. a PTY read).
    public func feed(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty else { return }
        scrollbackOffset = 0
        parser.parse(bytes, handler: self)
        delegate?.terminalDidUpdate(self)
    }

    /// Feeds a byte array from the host program into the parser.
    public func feed(_ bytes: [UInt8]) {
        feed(bytes[...])
    }

    /// Feeds a string (encoded as UTF-8) into the parser. Convenient for tests.
    public func feed(text: String) {
        feed(Array(text.utf8)[...])
    }

    /// Resizes the grid, preserving content where possible (no reflow).
    ///
    /// - Parameters:
    ///   - newCols: The new column count (must be positive).
    ///   - newRows: The new row count (must be positive).
    public func resize(cols newCols: Int, rows newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        guard newCols != cols || newRows != rows else { return }
        normalBuffer.resize(cols: newCols, rows: newRows, eraseCell: .blank)
        altBuffer.resize(cols: newCols, rows: newRows, eraseCell: .blank)
        cols = newCols
        rows = newRows
        delegate?.terminalDidUpdate(self)
    }

    // MARK: Rendering accessors

    /// Returns the line currently shown at the given viewport row (0 = top),
    /// accounting for any scrollback offset.
    ///
    /// - Parameter viewportRow: A row index in `0..<rows`.
    /// - Returns: The line to render at that row.
    public func displayLine(_ viewportRow: Int) -> BufferLine {
        buffer.displayLine(viewportRow, scrollOffset: scrollbackOffset)
    }

    /// The cursor position in viewport coordinates, or nil when hidden or scrolled away.
    public var displayCursor: Position? {
        guard cursorVisible, scrollbackOffset == 0 else { return nil }
        return Position(col: clampedX, row: buffer.cursorY)
    }

    /// The number of lines currently held in the scrollback history.
    public var scrollbackLineCount: Int { buffer.scrollbackLineCount }
    /// How many lines the viewport is currently scrolled up into history (0 = live tail).
    public var scrollOffset: Int { scrollbackOffset }

    /// Scrolls the viewport through the scrollback history.
    ///
    /// - Parameter delta: Lines to move; positive scrolls toward older history,
    ///   negative toward the live tail. Clamped to the available range.
    public func scrollViewport(byLines delta: Int) {
        let maxOffset = buffer.scrollbackLineCount
        let next = min(max(scrollbackOffset + delta, 0), maxOffset)
        guard next != scrollbackOffset else { return }
        scrollbackOffset = next
        delegate?.terminalDidUpdate(self)
    }

    // MARK: Mouse

    /// Reports a mouse event to the host program using the active mouse mode/encoding.
    ///
    /// Does nothing when mouse reporting is off.
    ///
    /// - Parameters:
    ///   - col: The zero-based cell column of the event.
    ///   - row: The zero-based cell row of the event.
    ///   - button: The button code (0 = left, 1 = middle, 2 = right).
    ///   - action: Whether the button was pressed, released, or dragged.
    public func sendMouse(col: Int, row: Int, button: Int, action: MouseAction) {
        guard mouseMode != .off else { return }
        let column = col + 1
        let line = row + 1
        switch mouseEncoding {
        case .sgr:
            var code = button
            if action == .drag { code += 32 }
            let final = action == .release ? "m" : "M"
            send(text: "\u{1b}[<\(code);\(column);\(line)\(final)")
        case .normal:
            let code = (action == .release ? 3 : button) + 32
            let bytes: [UInt8] = [
                0x1B, 0x5B, 0x4D,
                UInt8(min(255, code)),
                UInt8(min(255, column + 32)),
                UInt8(min(255, line + 32)),
            ]
            delegate?.terminalSend(self, data: bytes)
        }
    }

    // MARK: Helpers

    private var clampedX: Int { min(buffer.cursorX, cols - 1) }

    private var eraseCell: CharData {
        CharData(
            scalar: " ",
            attribute: Attribute(foreground: .defaultColor, background: currentAttribute.background, style: []),
            width: 1
        )
    }

    private func send(text: String) {
        delegate?.terminalSend(self, data: Array(text.utf8))
    }

    private func param(_ params: [Int], _ index: Int, default value: Int) -> Int {
        guard index < params.count else { return value }
        let raw = params[index]
        return raw == 0 ? value : raw
    }

    // MARK: Line movement

    private func lineFeed() {
        if buffer.cursorY == buffer.scrollBottom {
            buffer.scrollUp(eraseCell: eraseCell)
        } else if buffer.cursorY < rows - 1 {
            buffer.cursorY += 1
        }
    }

    private func reverseIndex() {
        if buffer.cursorY == buffer.scrollTop {
            buffer.scrollDown(eraseCell: eraseCell)
        } else if buffer.cursorY > 0 {
            buffer.cursorY -= 1
        }
    }

    // MARK: Cursor save/restore

    private func saveCursor() {
        buffer.savedCursorX = buffer.cursorX
        buffer.savedCursorY = buffer.cursorY
        buffer.savedAttribute = currentAttribute
    }

    private func restoreCursor() {
        buffer.cursorX = min(buffer.savedCursorX, cols - 1)
        buffer.cursorY = min(buffer.savedCursorY, rows - 1)
        currentAttribute = buffer.savedAttribute
    }

    // MARK: Alternate buffer

    private func switchAltBuffer(_ enable: Bool, save: Bool) {
        if enable {
            guard !usingAltBuffer else { return }
            if save { saveCursor() }
            altBuffer.clear(eraseCell: .blank)
            altBuffer.scrollTop = 0
            altBuffer.scrollBottom = rows - 1
            buffer = altBuffer
            usingAltBuffer = true
        } else {
            guard usingAltBuffer else { return }
            buffer = normalBuffer
            usingAltBuffer = false
            if save { restoreCursor() }
        }
        delegate?.terminalBufferActivated(self, usingAlt: usingAltBuffer)
    }

    private func reset() {
        currentAttribute = .default
        insertMode = false
        autoWrap = true
        cursorVisible = true
        applicationCursorKeys = false
        bracketedPasteEnabled = false
        mouseMode = .off
        mouseEncoding = .normal
        if usingAltBuffer {
            buffer = normalBuffer
            usingAltBuffer = false
        }
        normalBuffer.clear(eraseCell: .blank)
        altBuffer.clear(eraseCell: .blank)
        normalBuffer.scrollTop = 0
        normalBuffer.scrollBottom = rows - 1
        altBuffer.scrollTop = 0
        altBuffer.scrollBottom = rows - 1
        scrollbackOffset = 0
    }
}

// MARK: - ParserHandler

extension Terminal: ParserHandler {
    func parserPrint(_ scalar: Unicode.Scalar) {
        let width = UnicodeWidth.of(scalar)
        if width == 0 {
            attachCombiningMark(scalar)
            return
        }

        if buffer.cursorX + width > cols {
            if autoWrap {
                buffer.currentLine.isWrapped = true
                buffer.cursorX = 0
                lineFeed()
            } else {
                buffer.cursorX = cols - width
            }
        }

        let line = buffer.currentLine
        let x = buffer.cursorX
        guard x >= 0, x < cols else { return }

        if insertMode {
            line.insertCells(at: x, count: width, fill: eraseCell)
        }
        line[x] = CharData(scalar: scalar, attribute: currentAttribute, width: Int8(width))
        if width == 2, x + 1 < cols {
            line[x + 1] = CharData(scalar: " ", attribute: currentAttribute, width: 0)
        }
        buffer.cursorX += width
    }

    func parserExecute(_ control: UInt8) {
        switch control {
        case 0x07: // BEL
            delegate?.terminalBell(self)
        case 0x08: // BS
            if buffer.cursorX > 0 { buffer.cursorX = min(buffer.cursorX, cols) - 1 }
        case 0x09: // HT
            tabForward()
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            lineFeed()
        case 0x0D: // CR
            buffer.cursorX = 0
        default:
            break
        }
    }

    func parserCSIDispatch(final: UInt8, params: [Int], prefix: UInt8, intermediates: [UInt8]) {
        if prefix == 0x3F { // ? private modes
            switch final {
            case 0x68: setPrivateMode(params, value: true)  // h
            case 0x6C: setPrivateMode(params, value: false) // l
            default: break
            }
            return
        }

        switch final {
        case 0x41: cursorUp(param(params, 0, default: 1))        // A (CUU)
        case 0x42: cursorDown(param(params, 0, default: 1))      // B (CUD)
        case 0x43: cursorForward(param(params, 0, default: 1))   // C (CUF)
        case 0x44: cursorBackward(param(params, 0, default: 1))  // D (CUB)
        case 0x45: cursorNextLine(param(params, 0, default: 1))  // E (CNL)
        case 0x46: cursorPrevLine(param(params, 0, default: 1))  // F (CPL)
        case 0x47: setCursor(col: param(params, 0, default: 1) - 1) // G (CHA)
        case 0x48, 0x66: // H (CUP), f (HVP)
            setCursor(row: param(params, 0, default: 1) - 1, col: param(params, 1, default: 1) - 1)
        case 0x4A: eraseInDisplay(params.first ?? 0)             // J (ED)
        case 0x4B: eraseInLine(params.first ?? 0)               // K (EL)
        case 0x4C: insertLines(param(params, 0, default: 1))     // L (IL)
        case 0x4D: deleteLines(param(params, 0, default: 1))     // M (DL)
        case 0x40: insertChars(param(params, 0, default: 1))     // @ (ICH)
        case 0x50: deleteChars(param(params, 0, default: 1))     // P (DCH)
        case 0x58: eraseChars(param(params, 0, default: 1))      // X (ECH)
        case 0x53: scrollLines(up: true, count: param(params, 0, default: 1))   // S (SU)
        case 0x54: scrollLines(up: false, count: param(params, 0, default: 1))  // T (SD)
        case 0x64: setCursor(row: param(params, 0, default: 1) - 1)             // d (VPA)
        case 0x6D: applySGR(params)                              // m (SGR)
        case 0x72: setScrollRegion(params)                      // r (DECSTBM)
        case 0x68: setMode(params, value: true)                 // h
        case 0x6C: setMode(params, value: false)                // l
        case 0x6E: deviceStatusReport(params)                   // n (DSR)
        case 0x63: send(text: "\u{1b}[?1;2c")                   // c (DA)
        default:
            break
        }
    }

    func parserOSCDispatch(_ data: [UInt8]) {
        guard let separator = data.firstIndex(of: 0x3B) else { return }
        let code = Int(String(decoding: data[..<separator], as: UTF8.self)) ?? -1
        let text = String(decoding: data[(separator + 1)...], as: UTF8.self)
        if code == 0 || code == 2 {
            delegate?.terminalSetTitle(self, title: text)
        }
    }

    func parserESCDispatch(final: UInt8, intermediates: [UInt8]) {
        switch final {
        case 0x37: saveCursor()                         // ESC 7 (DECSC)
        case 0x38: restoreCursor()                      // ESC 8 (DECRC)
        case 0x44: lineFeed()                           // ESC D (IND)
        case 0x4D: reverseIndex()                       // ESC M (RI)
        case 0x45: buffer.cursorX = 0; lineFeed()       // ESC E (NEL)
        case 0x63: reset()                              // ESC c (RIS)
        default:
            break
        }
    }
}

// MARK: - Command implementations

private extension Terminal {
    /// Attaches a zero-width combining mark (e.g. NFD dakuten) to the most
    /// recently written cell so it renders as a single composed grapheme.
    func attachCombiningMark(_ scalar: Unicode.Scalar) {
        let line = buffer.currentLine
        var x = min(buffer.cursorX, cols) - 1
        guard x >= 0 else { return }
        if line[x].width == 0, x > 0 {
            x -= 1 // step back over the trailing half of a wide character
        }
        guard x >= 0, x < cols else { return }
        var cell = line[x]
        cell.combining.append(scalar)
        line[x] = cell
    }

    func tabForward() {
        var x = buffer.cursorX
        repeat {
            x += 1
        } while x % 8 != 0 && x < cols - 1
        buffer.cursorX = min(x, cols - 1)
    }

    func cursorUp(_ count: Int) {
        buffer.cursorY = max(buffer.cursorY - count, 0)
        buffer.cursorX = clampedX
    }

    func cursorDown(_ count: Int) {
        buffer.cursorY = min(buffer.cursorY + count, rows - 1)
        buffer.cursorX = clampedX
    }

    func cursorForward(_ count: Int) {
        buffer.cursorX = min(clampedX + count, cols - 1)
    }

    func cursorBackward(_ count: Int) {
        buffer.cursorX = max(clampedX - count, 0)
    }

    func cursorNextLine(_ count: Int) {
        buffer.cursorX = 0
        buffer.cursorY = min(buffer.cursorY + count, rows - 1)
    }

    func cursorPrevLine(_ count: Int) {
        buffer.cursorX = 0
        buffer.cursorY = max(buffer.cursorY - count, 0)
    }

    func setCursor(col: Int) {
        buffer.cursorX = min(max(col, 0), cols - 1)
    }

    func setCursor(row: Int) {
        buffer.cursorY = min(max(row, 0), rows - 1)
    }

    func setCursor(row: Int, col: Int) {
        buffer.cursorY = min(max(row, 0), rows - 1)
        buffer.cursorX = min(max(col, 0), cols - 1)
    }

    func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            buffer.currentLine.fill(eraseCell, from: clampedX, to: cols)
            var row = buffer.cursorY + 1
            while row < rows {
                buffer.line(atVisibleRow: row).fill(eraseCell, from: 0, to: cols)
                row += 1
            }
        case 1:
            var row = 0
            while row < buffer.cursorY {
                buffer.line(atVisibleRow: row).fill(eraseCell, from: 0, to: cols)
                row += 1
            }
            buffer.currentLine.fill(eraseCell, from: 0, to: clampedX + 1)
        case 2, 3:
            var row = 0
            while row < rows {
                buffer.line(atVisibleRow: row).fill(eraseCell, from: 0, to: cols)
                row += 1
            }
        default:
            break
        }
    }

    func eraseInLine(_ mode: Int) {
        switch mode {
        case 0: buffer.currentLine.fill(eraseCell, from: clampedX, to: cols)
        case 1: buffer.currentLine.fill(eraseCell, from: 0, to: clampedX + 1)
        case 2: buffer.currentLine.fill(eraseCell, from: 0, to: cols)
        default: break
        }
    }

    func insertLines(_ count: Int) {
        buffer.insertLines(at: buffer.cursorY, count: count, eraseCell: eraseCell)
    }

    func deleteLines(_ count: Int) {
        buffer.deleteLines(at: buffer.cursorY, count: count, eraseCell: eraseCell)
    }

    func insertChars(_ count: Int) {
        buffer.currentLine.insertCells(at: clampedX, count: count, fill: eraseCell)
    }

    func deleteChars(_ count: Int) {
        buffer.currentLine.deleteCells(at: clampedX, count: count, fill: eraseCell)
    }

    func eraseChars(_ count: Int) {
        buffer.currentLine.fill(eraseCell, from: clampedX, to: min(clampedX + count, cols))
    }

    func scrollLines(up: Bool, count: Int) {
        for _ in 0..<count {
            if up {
                buffer.scrollUp(eraseCell: eraseCell)
            } else {
                buffer.scrollDown(eraseCell: eraseCell)
            }
        }
    }

    func setScrollRegion(_ params: [Int]) {
        let top = (params.count >= 1 && params[0] != 0) ? params[0] - 1 : 0
        let bottom = (params.count >= 2 && params[1] != 0) ? params[1] - 1 : rows - 1
        guard top < bottom, bottom < rows, top >= 0 else { return }
        buffer.scrollTop = top
        buffer.scrollBottom = bottom
        buffer.cursorX = 0
        buffer.cursorY = 0
    }

    func setMode(_ params: [Int], value: Bool) {
        for code in params where code == 4 {
            insertMode = value
        }
    }

    func setPrivateMode(_ params: [Int], value: Bool) {
        for code in params {
            switch code {
            case 1: applicationCursorKeys = value
            case 7: autoWrap = value
            case 25: cursorVisible = value
            case 1000: mouseMode = value ? .normal : .off
            case 1002: mouseMode = value ? .buttonEvent : .off
            case 1003: mouseMode = value ? .anyEvent : .off
            case 1006: mouseEncoding = value ? .sgr : .normal
            case 2004: bracketedPasteEnabled = value
            case 47, 1047: switchAltBuffer(value, save: false)
            case 1049: switchAltBuffer(value, save: true)
            default: break
            }
        }
    }

    func deviceStatusReport(_ params: [Int]) {
        switch params.first ?? 0 {
        case 5: send(text: "\u{1b}[0n")
        case 6: send(text: "\u{1b}[\(buffer.cursorY + 1);\(clampedX + 1)R")
        default: break
        }
    }

    func applySGR(_ rawParams: [Int]) {
        let params = rawParams.isEmpty ? [0] : rawParams
        var index = 0
        while index < params.count {
            let code = params[index]
            switch code {
            case 0: currentAttribute = .default
            case 1: currentAttribute.style.insert(.bold)
            case 4: currentAttribute.style.insert(.underline)
            case 7: currentAttribute.style.insert(.inverse)
            case 22: currentAttribute.style.remove(.bold)
            case 24: currentAttribute.style.remove(.underline)
            case 27: currentAttribute.style.remove(.inverse)
            case 30...37: currentAttribute.foreground = .ansi(UInt8(code - 30))
            case 39: currentAttribute.foreground = .defaultColor
            case 40...47: currentAttribute.background = .ansi(UInt8(code - 40))
            case 49: currentAttribute.background = .defaultColor
            case 90...97: currentAttribute.foreground = .ansi(UInt8(code - 90 + 8))
            case 100...107: currentAttribute.background = .ansi(UInt8(code - 100 + 8))
            case 38, 48:
                if let (color, consumed) = parseExtendedColor(params, from: index) {
                    if code == 38 {
                        currentAttribute.foreground = color
                    } else {
                        currentAttribute.background = color
                    }
                    index += consumed
                }
            default:
                break
            }
            index += 1
        }
    }

    func parseExtendedColor(_ params: [Int], from index: Int) -> (TerminalColor, Int)? {
        guard index + 1 < params.count else { return nil }
        switch params[index + 1] {
        case 5:
            guard index + 2 < params.count else { return nil }
            return (.ansi(UInt8(min(255, max(0, params[index + 2])))), 2)
        case 2:
            guard index + 4 < params.count else { return nil }
            func channel(_ value: Int) -> UInt8 { UInt8(min(255, max(0, value))) }
            return (.rgb(red: channel(params[index + 2]),
                         green: channel(params[index + 3]),
                         blue: channel(params[index + 4])), 4)
        default:
            return nil
        }
    }
}
