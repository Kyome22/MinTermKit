import Testing
@testable import MinTermCore

@MainActor private func rowText(_ t: Terminal, _ r: Int) -> String {
    var s = ""; let line = t.displayLine(r)
    for c in 0..<t.cols { let cell = line[c]; if cell.width != 0 { s.unicodeScalars.append(cell.scalar) } }
    while s.last == " " { s.removeLast() }
    return s
}

@MainActor @Test func wideCharDeleteSequenceClearsCell() {
    let t = Terminal(cols: 20, rows: 3)
    // Exactly what UTF-8 zsh sends: echo あ, then delete via \b\b  \b\b
    t.feed([0xE3, 0x81, 0x82])             // あ
    #expect(rowText(t, 0) == "あ")
    #expect(t.displayCursor == Position(col: 2, row: 0))
    t.feed([0x08, 0x08, 0x20, 0x20, 0x08, 0x08]) // \b\b  \b\b
    #expect(rowText(t, 0) == "")           // あ fully erased
    #expect(t.displayCursor == Position(col: 0, row: 0))
}
