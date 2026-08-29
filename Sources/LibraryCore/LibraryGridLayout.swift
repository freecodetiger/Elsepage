import CoreGraphics

/// Geometry contract for the library grid.
public enum LibraryGridLayout {
    /// Default column count at standard Dynamic Type sizes.
    public static let columnCount = 2
    public static let coverAspectRatio: CGFloat = 2.0 / 3.0

    /// A11Y-01: at accessibility Dynamic Type sizes the fixed two-column cells
    /// get too narrow for the title/metadata text, so the grid falls back to a
    /// single readable column.
    public static func columnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 1 : columnCount
    }

    public static func columnWidth(
        containerWidth: CGFloat,
        horizontalPadding: CGFloat,
        columnSpacing: CGFloat,
        columnCount: Int? = nil
    ) -> CGFloat {
        let columns = max(1, columnCount ?? Self.columnCount)
        let available = containerWidth - (horizontalPadding * 2) - columnSpacing * CGFloat(columns - 1)
        return max(0, available / CGFloat(columns))
    }
}
