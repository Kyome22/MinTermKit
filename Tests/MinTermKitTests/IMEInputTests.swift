import Testing
import AppKit
@testable import MinTermKit

@MainActor
@Test func insertTextSendsCleanUTF8() {
    let session = TerminalSession()
    var sent: [UInt8] = []
    session.userInputObserver = { sent.append(contentsOf: $0) }

    let view = TerminalInputView()
    view.session = session
    // Simulate IME: mark then commit "あ"
    view.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(session.composingText == "あ")
    view.insertText("あ", replacementRange: NSRange(location: NSNotFound, length: 0))

    #expect(sent == Array("あ".utf8))
    #expect(session.composingText == "")
}

@MainActor
@Test func wideCharOccupiesTwoCells() {
    let t = Terminal(cols: 20, rows: 3)
    t.feed(text: "ああ")
    #expect(t.displayLine(0)[0].scalar == "あ")
    #expect(t.displayLine(0)[0].width == 2)
    #expect(t.displayLine(0)[1].width == 0)
    #expect(t.displayLine(0)[2].scalar == "あ")
    #expect(t.displayLine(0)[2].width == 2)
    #expect(t.displayCursor == Position(col: 4, row: 0))
}
