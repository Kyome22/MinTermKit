import AppKit
import CoreText
import SwiftUI
import MinTermCore

/// Draws the terminal grid into a SwiftUI `Canvas` via CoreText/CoreGraphics.
@MainActor
struct CanvasRenderer {
    let metrics: FontMetrics
    let foreground: NSColor
    let background: NSColor
    let cursorColor: NSColor
    let selectionColor: NSColor

    init(metrics: FontMetrics, theme: TerminalTheme = .default) {
        self.metrics = metrics
        self.foreground = NSColor(theme.foreground)
        self.background = NSColor(theme.background)
        self.cursorColor = NSColor(theme.cursor)
        self.selectionColor = NSColor(theme.selection)
    }

    func draw(_ context: GraphicsContext, size: CGSize, terminal: Terminal, selection: TerminalSelection?, composing: String = "") {
        context.withCGContext { cg in
            render(into: cg, size: size, terminal: terminal, selection: selection, composing: composing)
        }
    }

    func render(into cg: CGContext, size: CGSize, terminal: Terminal, selection: TerminalSelection?, composing: String = "") {
        cg.setFillColor(background.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))

        for row in 0..<terminal.rows {
            let selectedColumns = selection?.columns(onRow: row, cols: terminal.cols)
            drawLine(cg, line: terminal.displayLine(row), row: row, cols: terminal.cols, selected: selectedColumns)
        }

        if let cursor = terminal.displayCursor {
            if composing.isEmpty {
                drawCursor(cg, terminal: terminal, cursor: cursor)
            } else {
                drawComposing(cg, composing, cursor: cursor, cols: terminal.cols)
            }
        }
    }

    private func drawComposing(_ cg: CGContext, _ text: String, cursor: Position, cols: Int) {
        let cellWidth = metrics.cellWidth
        let cellHeight = metrics.cellHeight
        let yTop = CGFloat(cursor.row) * cellHeight
        let baseline = yTop + metrics.ascent
        var column = cursor.col
        let composingBackground = NSColor.controlAccentColor.withAlphaComponent(0.35)

        for scalar in text.unicodeScalars {
            let width = UnicodeWidth.of(scalar)
            if width == 0 { continue }
            let widthInCells = width == 2 ? 2 : 1
            if column + widthInCells > cols { break }

            cg.setFillColor(composingBackground.cgColor)
            cg.fill(CGRect(x: CGFloat(column) * cellWidth, y: yTop,
                           width: cellWidth * CGFloat(widthInCells), height: cellHeight))

            let cell = CharData(
                scalar: scalar,
                attribute: Attribute(foreground: .defaultColor, background: .defaultColor, style: .underline),
                width: Int8(width)
            )
            drawGlyph(cg, cell: cell, color: foreground, x: CGFloat(column) * cellWidth, baseline: baseline)
            column += widthInCells
        }
    }

    private func drawLine(_ cg: CGContext, line: BufferLine, row: Int, cols: Int, selected: ClosedRange<Int>?) {
        let cellWidth = metrics.cellWidth
        let cellHeight = metrics.cellHeight
        let yTop = CGFloat(row) * cellHeight

        // Pass 1: background fills.
        var column = 0
        while column < cols {
            let cell = line[column]
            if cell.width == 0 {
                column += 1
                continue
            }
            let widthInCells = cell.width == 2 ? 2 : 1
            let (_, fillColor) = resolveColors(cell.attribute)
            if let fillColor {
                cg.setFillColor(fillColor.cgColor)
                cg.fill(CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: yTop,
                    width: cellWidth * CGFloat(widthInCells),
                    height: cellHeight
                ))
            }
            column += widthInCells
        }

        if let selected {
            cg.setFillColor(selectionColor.withAlphaComponent(0.5).cgColor)
            cg.fill(CGRect(
                x: CGFloat(selected.lowerBound) * cellWidth,
                y: yTop,
                width: CGFloat(selected.count) * cellWidth,
                height: cellHeight
            ))
        }

        // Pass 2: glyphs, each pinned to its own cell so the grid never drifts.
        let baseline = yTop + metrics.ascent
        column = 0
        while column < cols {
            let cell = line[column]
            if cell.width == 0 {
                column += 1
                continue
            }
            let widthInCells = cell.width == 2 ? 2 : 1
            if cell.scalar != " " || !cell.combining.isEmpty {
                let (textColor, _) = resolveColors(cell.attribute)
                drawGlyph(cg, cell: cell, color: textColor, x: CGFloat(column) * cellWidth, baseline: baseline)
            }
            column += widthInCells
        }
    }

    private func drawGlyph(_ cg: CGContext, cell: CharData, color: NSColor, x: CGFloat, baseline: CGFloat) {
        let ctLine = CTLineCreateWithAttributedString(attributedCell(cell, color: color))
        let slotWidth = metrics.cellWidth * CGFloat(cell.width == 2 ? 2 : 1)
        let glyphWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))

        if glyphWidth > slotWidth, glyphWidth > 0 {
            // Glyph wider than its slot: scale it down horizontally to fit.
            let scale = slotWidth / glyphWidth
            cg.textMatrix = CGAffineTransform(scaleX: scale, y: -1)
            cg.textPosition = CGPoint(x: x, y: baseline)
        } else {
            // Center the glyph within its slot so narrow CJK glyphs aren't left-pinned.
            cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            let offset = max(0, (slotWidth - glyphWidth) / 2)
            cg.textPosition = CGPoint(x: x + offset, y: baseline)
        }
        CTLineDraw(ctLine, cg)
    }

    private func drawCursor(_ cg: CGContext, terminal: Terminal, cursor: Position) {
        let cellWidth = metrics.cellWidth
        let cellHeight = metrics.cellHeight
        let rect = CGRect(
            x: CGFloat(cursor.col) * cellWidth,
            y: CGFloat(cursor.row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        cg.setFillColor(cursorColor.cgColor)
        cg.fill(rect)

        let cell = terminal.displayLine(cursor.row)[cursor.col]
        if cell.scalar != " " {
            drawGlyph(cg, cell: cell, color: background, x: rect.minX, baseline: rect.minY + metrics.ascent)
        }
    }

    private func attributedCell(_ cell: CharData, color: NSColor) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: cell.attribute.style.contains(.bold) ? metrics.boldFont : metrics.font,
            .foregroundColor: color,
        ]
        if cell.attribute.style.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: cell.displayText, attributes: attributes)
    }

    /// Returns the text color and (optional) background fill color for a cell,
    /// accounting for the inverse attribute.
    private func resolveColors(_ attribute: Attribute) -> (text: NSColor, fill: NSColor?) {
        var foregroundColor = attribute.foreground
        var backgroundColor = attribute.background
        if attribute.style.contains(.inverse) {
            swap(&foregroundColor, &backgroundColor)
        }

        let text = nsColor(foregroundColor, default: foreground)
        let needsFill = attribute.style.contains(.inverse) || !isDefault(backgroundColor)
        let fill = needsFill ? nsColor(backgroundColor, default: background) : nil
        return (text, fill)
    }

    private func isDefault(_ color: TerminalColor) -> Bool {
        if case .defaultColor = color { return true }
        return false
    }

    private func nsColor(_ color: TerminalColor, default fallback: NSColor) -> NSColor {
        switch color {
        case .defaultColor:
            return fallback
        case .ansi(let index):
            let rgb = Palette.rgb(forAnsi: Int(index))
            return NSColor(
                srgbRed: CGFloat(rgb.red) / 255,
                green: CGFloat(rgb.green) / 255,
                blue: CGFloat(rgb.blue) / 255,
                alpha: 1
            )
        case .rgb(let red, let green, let blue):
            return NSColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }
    }
}
