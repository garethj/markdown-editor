import AppKit

/// Renders a markdown table as a grid with cell wrapping, positioned over the text view.
final class TableOverlayView: NSView {
    let tableData: TableData
    private var columnWidths: [CGFloat] = []
    private var cellViews: [[NSTextField]] = []
    private let gridLineWidth: CGFloat = 0.5
    private let cellPadding: CGFloat = 8

    /// Called when the user clicks on a cell. Passes the cell's character range in the backing store.
    var onCellClicked: ((NSRange) -> Void)?

    init(tableData: TableData, availableWidth: CGFloat) {
        self.tableData = tableData
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = MarkdownTheme.shared.tableOverlayBackgroundColor.cgColor
        buildGrid(availableWidth: availableWidth)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Recalculate column widths and rebuild when width changes.
    func updateWidth(_ availableWidth: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        cellViews.removeAll()
        buildGrid(availableWidth: availableWidth)
    }

    // MARK: - Click handling

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        // Find which cell was clicked
        for (rowIdx, row) in cellViews.enumerated() {
            for (colIdx, field) in row.enumerated() {
                // Use the column/row area (not just the text field frame which has padding)
                let colX = columnWidths.prefix(colIdx).reduce(0, +)
                let rowY = field.frame.origin.y - 4  // account for vertical padding
                let cellRect = NSRect(
                    x: colX,
                    y: rowY,
                    width: columnWidths[colIdx],
                    height: field.frame.height + 8
                )
                if cellRect.contains(localPoint) {
                    if rowIdx < tableData.rows.count, colIdx < tableData.rows[rowIdx].count {
                        let cell = tableData.rows[rowIdx][colIdx]
                        onCellClicked?(cell.charRange)
                        return
                    }
                }
            }
        }

        // Fallback: clicked outside any cell, use table start
        onCellClicked?(tableData.charRange)
    }

    // MARK: - Grid building

    private func buildGrid(availableWidth: CGFloat) {
        columnWidths = computeColumnWidths(availableWidth: availableWidth)

        let colCount = tableData.columnCount
        guard colCount > 0, !tableData.rows.isEmpty else { return }

        var yOffset: CGFloat = 0

        for (rowIdx, row) in tableData.rows.enumerated() {
            var rowCells: [NSTextField] = []
            var maxHeight: CGFloat = 0

            for colIdx in 0..<colCount {
                let cell = colIdx < row.count ? row[colIdx] : nil

                let field = makeCell(
                    attributedText: cell?.attributedText,
                    width: columnWidths[colIdx]
                )

                let height = field.fittingSize.height
                maxHeight = max(maxHeight, height)
                rowCells.append(field)
            }

            // Add vertical padding
            maxHeight += 8

            for (colIdx, field) in rowCells.enumerated() {
                let x = columnWidths.prefix(colIdx).reduce(0, +)
                field.frame = NSRect(
                    x: x + cellPadding,
                    y: yOffset + 4,
                    width: columnWidths[colIdx] - cellPadding * 2,
                    height: maxHeight - 8
                )
                addSubview(field)
            }

            cellViews.append(rowCells)
            yOffset += maxHeight
        }

        frame.size = NSSize(
            width: columnWidths.reduce(0, +),
            height: yOffset
        )
    }

    private func makeCell(attributedText: NSAttributedString?, width: CGFloat) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        if let attrText = attributedText {
            field.attributedStringValue = attrText
        }
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byWordWrapping
        field.preferredMaxLayoutWidth = width - cellPadding * 2
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        return field
    }

    private func computeColumnWidths(availableWidth: CGFloat) -> [CGFloat] {
        let theme = MarkdownTheme.shared
        let colCount = tableData.columnCount
        guard colCount > 0 else { return [] }

        let naturalWidths = tableData.maxColumnWidths
        let totalNatural = naturalWidths.reduce(0, +)

        // If it all fits, use natural widths
        if totalNatural <= availableWidth {
            return Array(naturalWidths.prefix(colCount))
        }

        // Distribute proportionally with min/max constraints
        let minWidth = theme.tableOverlayMinColumnWidth
        let maxWidth = availableWidth * theme.tableOverlayMaxColumnFraction

        var widths = (0..<colCount).map { col -> CGFloat in
            let natural = col < naturalWidths.count ? naturalWidths[col] : minWidth
            let proportional = availableWidth * (natural / max(totalNatural, 1))
            return min(max(proportional, minWidth), maxWidth)
        }

        // Normalize to fit available width
        let totalComputed = widths.reduce(0, +)
        if totalComputed > 0 {
            let scale = availableWidth / totalComputed
            widths = widths.map { $0 * scale }
        }

        return widths
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gridColor = MarkdownTheme.shared.tableOverlayGridColor
        gridColor.setStroke()

        let path = NSBezierPath()
        path.lineWidth = gridLineWidth

        // Vertical lines between columns
        var x: CGFloat = 0
        for colIdx in 0..<tableData.columnCount {
            x += columnWidths[colIdx]
            if colIdx < tableData.columnCount - 1 {
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.height))
            }
        }

        // Horizontal lines between rows — line after header is slightly thicker
        for rowIdx in 0..<cellViews.count {
            if let firstCell = cellViews[rowIdx].first {
                let y = firstCell.frame.maxY + 4  // bottom of row including padding
                if rowIdx < cellViews.count - 1 {
                    let linePath = NSBezierPath()
                    linePath.lineWidth = rowIdx == 0 ? 1.0 : gridLineWidth
                    linePath.move(to: NSPoint(x: 0, y: y))
                    linePath.line(to: NSPoint(x: bounds.width, y: y))
                    linePath.stroke()
                }
            }
        }

        // Border
        let border = NSBezierPath(rect: bounds.insetBy(dx: gridLineWidth / 2, dy: gridLineWidth / 2))
        border.lineWidth = gridLineWidth
        border.stroke()

        path.stroke()
    }
}
