import CoreGraphics

/// Where a dragged window can be dropped on one display: a grid of cells over the usable area
/// (below the menu bar, beside the Dock). Hovering a cell targets it, hovering the line between
/// two cells targets both, and the top edge targets the whole area. Cocoa coordinates.
struct ZoneLayout: Equatable {
    let area: CGRect
    let columns: Int
    let rows: Int

    /// How close to the top edge the pointer must be to target the whole area.
    static let fillReach: CGFloat = 24

    /// Two by two on an ordinary display, three columns on an ultrawide, two rows standing up.
    init(area: CGRect) {
        self.area = area
        switch area.width / max(area.height, 1) {
        case ..<0.9: (columns, rows) = (1, 2)
        case 2.1...: (columns, rows) = (3, 1)
        default: (columns, rows) = (2, 2)
        }
    }

    private var cellWidth: CGFloat { area.width / CGFloat(columns) }
    private var cellHeight: CGFloat { area.height / CGFloat(rows) }

    /// How close to a divider the pointer must be to span the cells on both sides of it.
    private var spanReach: CGFloat { min(60, cellWidth / 4, cellHeight / 4) }

    /// Every cell, left to right and top to bottom.
    var cells: [CGRect] {
        (0..<rows).flatMap { row in (0..<columns).map { column in rect(columns: column...column, rows: row...row) } }
    }

    /// The zone under the pointer, or nil when the pointer is off this display's usable area.
    /// The menu bar above the area counts as its top edge.
    func target(for point: CGPoint) -> CGRect? {
        guard point.x >= area.minX, point.x <= area.maxX, point.y >= area.minY else { return nil }
        if point.y >= area.maxY - Self.fillReach { return area }

        let x = point.x - area.minX
        let y = area.maxY - point.y
        let column = min(Int(x / cellWidth), columns - 1)
        let row = min(Int(y / cellHeight), rows - 1)
        return rect(
            columns: span(x, cell: cellWidth, count: columns) ?? column...column,
            rows: span(y, cell: cellHeight, count: rows) ?? row...row
        )
    }

    /// Where a window of `size` ends up in `zone`: filling it when the window can be resized,
    /// centred in it when it cannot, and nowhere when it does not fit.
    static func dropFrame(in zone: CGRect, windowSize size: CGSize, resizable: Bool) -> CGRect? {
        if resizable { return zone }
        guard size.width <= zone.width, size.height <= zone.height else { return nil }
        return CGRect(
            x: (zone.midX - size.width / 2).rounded(), y: (zone.midY - size.height / 2).rounded(),
            width: size.width, height: size.height
        )
    }

    /// The two cells either side of the divider nearest to `offset`, when it is within reach.
    private func span(_ offset: CGFloat, cell: CGFloat, count: Int) -> ClosedRange<Int>? {
        let divider = Int((offset / cell).rounded())
        guard divider > 0, divider < count, abs(offset - CGFloat(divider) * cell) < spanReach else { return nil }
        return (divider - 1)...divider
    }

    /// Cells counted from the top-left, as one rectangle on whole points.
    private func rect(columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> CGRect {
        let minX = (area.minX + CGFloat(columns.lowerBound) * cellWidth).rounded()
        let maxX = (area.minX + CGFloat(columns.upperBound + 1) * cellWidth).rounded()
        let maxY = (area.maxY - CGFloat(rows.lowerBound) * cellHeight).rounded()
        let minY = (area.maxY - CGFloat(rows.upperBound + 1) * cellHeight).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
