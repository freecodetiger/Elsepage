import CoreGraphics

/// Geometry contract for the two-column library grid.
public enum LibraryGridLayout {
    public static let columnCount = 2
    public static let coverAspectRatio: CGFloat = 2.0 / 3.0

    public static func columnWidth(
        containerWidth: CGFloat,
        horizontalPadding: CGFloat,
        columnSpacing: CGFloat
    ) -> CGFloat {
        let available = containerWidth - (horizontalPadding * 2) - columnSpacing
        return max(0, available / CGFloat(columnCount))
    }
}
