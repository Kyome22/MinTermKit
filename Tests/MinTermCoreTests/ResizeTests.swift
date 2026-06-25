import Testing
@testable import MinTermCore

@MainActor
@Test func resizeStressDoesNotCrash() {
    let terminal = Terminal(cols: 80, rows: 24)
    for i in 0..<60 { terminal.feed(text: "line\(i) some content here\r\n") }
    let sizes = [(1,1),(200,60),(40,10),(80,24),(10,3),(120,40),(5,50),(80,1),(1,40)]
    for (c, r) in sizes {
        terminal.resize(cols: c, rows: r)
        for row in 0..<r {
            let line = terminal.displayLine(row)
            for col in 0..<c { _ = line[col] }
        }
        terminal.feed(text: "x\r\n")
    }
    #expect(terminal.cols >= 1)
}
