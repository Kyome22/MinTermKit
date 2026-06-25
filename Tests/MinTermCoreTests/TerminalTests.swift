import Testing
@testable import MinTermCore

@MainActor
private func makeTerminal(cols: Int = 20, rows: Int = 5) -> Terminal {
    Terminal(cols: cols, rows: rows)
}

private func text(of line: BufferLine, cols: Int) -> String {
    var result = ""
    var index = 0
    while index < cols {
        let cell = line[index]
        if cell.width == 0 {
            index += 1
            continue
        }
        result.unicodeScalars.append(cell.scalar)
        index += 1
    }
    return result.trimmingTrailingSpaces()
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var view = self
        while view.last == " " {
            view.removeLast()
        }
        return view
    }
}

@MainActor
@Test func printsPlainText() {
    let terminal = makeTerminal()
    terminal.feed(text: "hello")
    #expect(text(of: terminal.displayLine(0), cols: 20) == "hello")
    #expect(terminal.displayCursor == Position(col: 5, row: 0))
}

@MainActor
@Test func carriageReturnAndLineFeed() {
    let terminal = makeTerminal()
    terminal.feed(text: "ab\r\ncd")
    #expect(text(of: terminal.displayLine(0), cols: 20) == "ab")
    #expect(text(of: terminal.displayLine(1), cols: 20) == "cd")
}

@MainActor
@Test func cursorPositionAndErase() {
    let terminal = makeTerminal()
    terminal.feed(text: "ABCDE")
    // Move cursor to row 1, col 1 (CUP) then erase from cursor to end of display.
    terminal.feed(text: "\u{1b}[1;3H\u{1b}[0J")
    #expect(text(of: terminal.displayLine(0), cols: 20) == "AB")
}

@MainActor
@Test func sgrColorIsApplied() {
    let terminal = makeTerminal()
    terminal.feed(text: "\u{1b}[31mR\u{1b}[0m")
    let cell = terminal.displayLine(0)[0]
    #expect(cell.attribute.foreground == .ansi(1))
}

@MainActor
@Test func lineWrapAdvancesRow() {
    let terminal = makeTerminal(cols: 4, rows: 4)
    terminal.feed(text: "abcdef")
    #expect(text(of: terminal.displayLine(0), cols: 4) == "abcd")
    #expect(text(of: terminal.displayLine(1), cols: 4) == "ef")
}

@MainActor
@Test func scrollbackRetainsHistory() {
    let terminal = makeTerminal(cols: 6, rows: 2)
    terminal.feed(text: "one\r\ntwo\r\nthree")
    // Visible rows should now show the last two logical lines.
    #expect(text(of: terminal.displayLine(0), cols: 6) == "two")
    #expect(text(of: terminal.displayLine(1), cols: 6) == "three")
    #expect(terminal.scrollbackLineCount == 1)
}

@MainActor
@Test func alternateBufferSwitch() {
    let terminal = makeTerminal()
    terminal.feed(text: "normal")
    terminal.feed(text: "\u{1b}[?1049h")
    #expect(terminal.usingAltBuffer)
    #expect(text(of: terminal.displayLine(0), cols: 20) == "")
    terminal.feed(text: "\u{1b}[?1049l")
    #expect(!terminal.usingAltBuffer)
    #expect(text(of: terminal.displayLine(0), cols: 20) == "normal")
}

@MainActor
@Test func scrollRegionScrollsOnlyWithinRegion() {
    let terminal = makeTerminal(cols: 4, rows: 4)
    terminal.feed(text: "0\r\n1\r\n2\r\n3")
    terminal.feed(text: "\u{1b}[2;3r") // DECSTBM: region rows 2..3 (indices 1..2)
    terminal.feed(text: "\u{1b}[3;1H") // cursor to row index 2 (bottom of region)
    terminal.feed(text: "\n")           // LF scrolls only the region
    #expect(text(of: terminal.displayLine(0), cols: 4) == "0")
    #expect(text(of: terminal.displayLine(1), cols: 4) == "2")
    #expect(text(of: terminal.displayLine(2), cols: 4) == "")
    #expect(text(of: terminal.displayLine(3), cols: 4) == "3")
}

@Test func applicationCursorKeysChangesEncoding() {
    #expect(KeyEncoder.encode(.up, applicationCursor: false) == [0x1B, 0x5B, 0x41])
    #expect(KeyEncoder.encode(.up, applicationCursor: true) == [0x1B, 0x4F, 0x41])
}

@MainActor
@Test func sgrMouseReportIsEmitted() {
    final class Sink: TerminalDelegate {
        var sent: [UInt8] = []
        func terminalSend(_ terminal: Terminal, data: [UInt8]) { sent.append(contentsOf: data) }
    }
    let terminal = makeTerminal()
    let sink = Sink()
    terminal.delegate = sink
    terminal.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
    sink.sent.removeAll()
    terminal.sendMouse(col: 4, row: 2, button: 0, action: .press)
    #expect(String(decoding: sink.sent, as: UTF8.self) == "\u{1b}[<0;5;3M")
}

@MainActor
@Test func cursorPositionReport() {
    final class Sink: TerminalDelegate {
        var sent: [UInt8] = []
        func terminalSend(_ terminal: Terminal, data: [UInt8]) { sent.append(contentsOf: data) }
    }
    let terminal = makeTerminal()
    let sink = Sink()
    terminal.delegate = sink
    terminal.feed(text: "\u{1b}[3;5H\u{1b}[6n")
    #expect(String(decoding: sink.sent, as: UTF8.self) == "\u{1b}[3;5R")
}
