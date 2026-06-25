/// A zero-based cell coordinate in the terminal grid.
public struct Position: Equatable, Sendable {
    /// The column (x), counted from the left edge.
    public var col: Int
    /// The row (y), counted from the top of the viewport.
    public var row: Int

    /// Creates a position at the given column and row.
    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}
