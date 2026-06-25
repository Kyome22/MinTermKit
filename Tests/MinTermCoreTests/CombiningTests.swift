import Testing
@testable import MinTermCore

@MainActor @Test func combiningDakutenAttachesToBaseCell() {
    let t = Terminal(cols: 20, rows: 3)
    // NFD form as macOS filesystems emit: シ (U+30B7) + combining voiced mark (U+3099) = ジ
    t.feed(text: "シ\u{3099}")
    let cell = t.displayLine(0)[0]
    #expect(cell.scalar == "シ")
    #expect(cell.combining == ["\u{3099}"])
    #expect(cell.displayText == "シ\u{3099}")
    #expect(cell.width == 2)
    // The combining mark must NOT occupy its own cell or advance the cursor.
    #expect(t.displayLine(0)[2].combining.isEmpty)
    #expect(t.displayCursor == Position(col: 2, row: 0))
}
