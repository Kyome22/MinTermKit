/// One screen of terminal content: a fixed grid of `rows` visible lines plus,
/// optionally, a bounded scrollback history.
final class Buffer {
    private(set) var cols: Int
    private(set) var rows: Int

    /// Exactly `rows` visible lines, top to bottom.
    private(set) var screen: [BufferLine]
    /// History lines that scrolled off the top (oldest first). Empty for the alt buffer.
    private(set) var scrollback: [BufferLine]

    let allowsScrollback: Bool
    let scrollbackLimit: Int

    var cursorX = 0
    var cursorY = 0

    /// Scroll region, inclusive, in visible-row coordinates.
    var scrollTop = 0
    var scrollBottom: Int

    var savedCursorX = 0
    var savedCursorY = 0
    var savedAttribute: Attribute = .default

    init(cols: Int, rows: Int, allowsScrollback: Bool, scrollbackLimit: Int) {
        self.cols = cols
        self.rows = rows
        self.allowsScrollback = allowsScrollback
        self.scrollbackLimit = scrollbackLimit
        self.scrollBottom = rows - 1
        self.screen = (0..<rows).map { _ in BufferLine(cols: cols) }
        self.scrollback = []
    }

    var scrollbackLineCount: Int { scrollback.count }

    var currentLine: BufferLine {
        screen[min(max(cursorY, 0), rows - 1)]
    }

    /// Clears all visible lines (not the scrollback) and homes the cursor.
    func clear(eraseCell: CharData) {
        for line in screen {
            line.fill(eraseCell, from: 0, to: cols)
            line.isWrapped = false
        }
        cursorX = 0
        cursorY = 0
    }

    func line(atVisibleRow row: Int) -> BufferLine {
        screen[min(max(row, 0), rows - 1)]
    }

    // MARK: Scrolling

    /// Scrolls the active region up by one line. When the region is the whole
    /// screen and scrollback is allowed, the top line is pushed into history.
    func scrollUp(eraseCell: CharData) {
        if scrollTop == 0 && scrollBottom == rows - 1 {
            let removed = screen.removeFirst()
            if allowsScrollback {
                scrollback.append(removed)
                if scrollback.count > scrollbackLimit {
                    scrollback.removeFirst()
                }
            }
            screen.append(blankLine(eraseCell))
        } else {
            var index = scrollTop
            while index < scrollBottom {
                screen[index] = screen[index + 1]
                index += 1
            }
            screen[scrollBottom] = blankLine(eraseCell)
        }
    }

    /// Scrolls the active region down by one line, inserting a blank at the top.
    func scrollDown(eraseCell: CharData) {
        var index = scrollBottom
        while index > scrollTop {
            screen[index] = screen[index - 1]
            index -= 1
        }
        screen[scrollTop] = blankLine(eraseCell)
    }

    func insertLines(at row: Int, count: Int, eraseCell: CharData) {
        guard row >= scrollTop && row <= scrollBottom else { return }
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(blankLine(eraseCell), at: row)
        }
    }

    func deleteLines(at row: Int, count: Int, eraseCell: CharData) {
        guard row >= scrollTop && row <= scrollBottom else { return }
        for _ in 0..<count {
            screen.remove(at: row)
            screen.insert(blankLine(eraseCell), at: scrollBottom)
        }
    }

    private func blankLine(_ eraseCell: CharData) -> BufferLine {
        BufferLine(cols: cols, fill: eraseCell)
    }

    // MARK: Resize

    func resize(cols newCols: Int, rows newRows: Int, eraseCell: CharData) {
        if newCols != cols {
            for line in screen {
                line.resize(cols: newCols, fill: eraseCell)
            }
            for line in scrollback {
                line.resize(cols: newCols, fill: eraseCell)
            }
            cols = newCols
        }

        if newRows != rows {
            if newRows < rows {
                let remove = rows - newRows
                for _ in 0..<remove {
                    if cursorY < screen.count - 1 {
                        // Prefer removing blank/extra lines below the cursor first.
                        screen.removeLast()
                    } else {
                        // Cursor is on the last line: push the top line into scrollback.
                        let top = screen.removeFirst()
                        if allowsScrollback {
                            scrollback.append(top)
                            if scrollback.count > scrollbackLimit {
                                scrollback.removeFirst()
                            }
                        }
                        cursorY -= 1
                    }
                }
            } else {
                let add = newRows - rows
                for _ in 0..<add {
                    if allowsScrollback, let restored = scrollback.popLast() {
                        screen.insert(restored, at: 0)
                        cursorY += 1
                    } else {
                        screen.append(BufferLine(cols: cols, fill: eraseCell))
                    }
                }
            }
            rows = newRows
            scrollTop = 0
            scrollBottom = rows - 1
            cursorY = min(cursorY, rows - 1)
        }

        cursorX = min(cursorX, cols - 1)
    }

    // MARK: Display

    /// Returns the line shown at `viewportRow` given a scrollback offset
    /// (0 = live tail). Offsets count lines scrolled up into history.
    func displayLine(_ viewportRow: Int, scrollOffset: Int) -> BufferLine {
        let historyCount = scrollback.count
        let top = historyCount - scrollOffset
        let index = top + viewportRow
        if index < 0 {
            return emptyLine
        }
        if index < historyCount {
            return scrollback[index]
        }
        let screenIndex = index - historyCount
        if screenIndex >= 0 && screenIndex < screen.count {
            return screen[screenIndex]
        }
        return emptyLine
    }

    private lazy var emptyLine = BufferLine(cols: cols)
}
