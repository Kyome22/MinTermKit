/// A single line of terminal cells. Reference type so lines can be moved
/// cheaply between the screen and the scrollback.
public final class BufferLine {
    private var cells: [CharData]
    /// True when this line continues onto the next (soft-wrapped) line.
    public internal(set) var isWrapped = false

    init(cols: Int, fill: CharData = .blank) {
        cells = Array(repeating: fill, count: cols)
    }

    /// The number of cells in the line.
    public var count: Int { cells.count }

    /// Reads the cell at the given column index. (Mutation is engine-internal.)
    public internal(set) subscript(_ index: Int) -> CharData {
        get { cells[index] }
        set { cells[index] = newValue }
    }

    func fill(_ value: CharData, from: Int, to: Int) {
        var index = max(0, from)
        let end = min(to, cells.count)
        while index < end {
            cells[index] = value
            index += 1
        }
    }

    /// Grows the backing storage to `cols` if needed. Storage is never shrunk so
    /// that content beyond a narrowed width is preserved and reappears when the
    /// terminal is widened again (no reflow, but no data loss).
    func resize(cols: Int, fill: CharData) {
        if cols > cells.count {
            cells.append(contentsOf: repeatElement(fill, count: cols - cells.count))
        }
    }

    func insertCells(at position: Int, count: Int, fill: CharData) {
        let total = cells.count
        guard position < total else { return }
        var index = total - 1
        while index >= position + count {
            cells[index] = cells[index - count]
            index -= 1
        }
        var clear = position
        while clear < min(position + count, total) {
            cells[clear] = fill
            clear += 1
        }
    }

    func deleteCells(at position: Int, count: Int, fill: CharData) {
        let total = cells.count
        guard position < total else { return }
        var index = position
        while index < total - count {
            cells[index] = cells[index + count]
            index += 1
        }
        while index < total {
            cells[index] = fill
            index += 1
        }
    }
}
