import MinTermCore

/// A text selection expressed in viewport cell coordinates (anchor = where it
/// began, head = the moving endpoint).
struct TerminalSelection: Equatable, Sendable {
    var anchor: Position
    var head: Position

    /// Returns the endpoints ordered top-to-bottom, left-to-right.
    func normalized() -> (start: Position, end: Position) {
        if anchor.row != head.row {
            return anchor.row < head.row ? (anchor, head) : (head, anchor)
        }
        return anchor.col <= head.col ? (anchor, head) : (head, anchor)
    }

    /// The inclusive column range selected on `row`, or nil if none.
    func columns(onRow row: Int, cols: Int) -> ClosedRange<Int>? {
        let (start, end) = normalized()
        guard row >= start.row, row <= end.row else { return nil }
        let from = row == start.row ? start.col : 0
        let to = row == end.row ? end.col : cols - 1
        guard from <= to else { return nil }
        return max(0, from)...min(cols - 1, to)
    }
}
