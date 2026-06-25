import Testing
@testable import MinTermCore

@MainActor private func rowText(_ t: Terminal, _ r: Int) -> String {
    var s = ""; let line = t.displayLine(r)
    for c in 0..<t.cols { let cell = line[c]; if cell.width != 0 { s.unicodeScalars.append(cell.scalar) } }
    while s.last == " " { s.removeLast() }
    return s
}

@MainActor @Test func resizeNarrowerKeepsContent() {
    let t = Terminal(cols: 20, rows: 5)
    t.feed(text: "ABCDEFGHIJ")
    t.resize(cols: 8, rows: 5)
    #expect(rowText(t, 0) == "ABCDEFGH")  // truncated to 8, content kept
}

@MainActor @Test func wideningAfterNarrowingRestoresContent() {
    let t = Terminal(cols: 20, rows: 3)
    t.feed(text: "ABCDEFGHIJKLMNOP") // 16 chars
    t.resize(cols: 8, rows: 3)
    #expect(rowText(t, 0) == "ABCDEFGH") // visible width narrowed
    t.resize(cols: 20, rows: 3)
    #expect(rowText(t, 0) == "ABCDEFGHIJKLMNOP") // content restored, not lost
}

@MainActor @Test func resizeShorterRemovesBlankLinesBelowCursorFirst() {
    let t = Terminal(cols: 10, rows: 6)
    t.feed(text: "A\r\nB\r\nC") // cursor on "C" at row 2; rows 3..5 blank
    t.resize(cols: 10, rows: 3)
    #expect(rowText(t, 0) == "A")
    #expect(rowText(t, 1) == "B")
    #expect(rowText(t, 2) == "C")
    #expect(t.scrollbackLineCount == 0) // content kept; only blank lines removed
}

@MainActor @Test func resizeShorterMovesToScrollback() {
    let t = Terminal(cols: 10, rows: 5)
    t.feed(text: "L0\r\nL1\r\nL2\r\nL3\r\nL4")  // 5 rows, cursor at row4
    t.resize(cols: 10, rows: 3)
    // bottom 3 rows visible, top 2 in scrollback
    #expect(rowText(t, 0) == "L2")
    #expect(rowText(t, 2) == "L4")
    #expect(t.scrollbackLineCount == 2)
}
