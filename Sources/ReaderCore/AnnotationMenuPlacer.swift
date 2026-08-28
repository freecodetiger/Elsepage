import CoreGraphics

/// Pure geometry for anchoring in-place annotation UI near a content rect.
///
/// All values live in one shared coordinate space: the anchor comes from the
/// Readium navigator view (which fills the screen edge to edge), so the
/// container is that same full-screen space. No UIKit types, so placement
/// rules are unit-testable on every platform.
public enum AnnotationMenuPlacer {

    /// Top-left origin for a menu of `menuSize` anchored to `anchor`.
    ///
    /// - Prefers sitting above the anchor with `gap` spacing, so the menu and
    ///   its anchor stay on the same screen the user is looking at.
    /// - Falls back to below the anchor when there is no room above.
    /// - When neither side fits (rare, only for huge anchors) the menu pins to
    ///   the top margin rather than being pushed off screen.
    /// - `anchor == nil` (geometry unavailable, e.g. arriving from a jump)
    ///   docks at the bottom of the container, covering little content.
    public static func origin(
        anchor: CGRect?,
        menuSize: CGSize,
        container: CGRect,
        margin: CGFloat,
        gap: CGFloat
    ) -> CGPoint {
        guard menuSize.width > 0, menuSize.height > 0 else {
            return CGPoint(x: container.midX, y: container.midY)
        }
        guard let anchor, !anchor.isNull else {
            return CGPoint(
                x: container.midX - menuSize.width / 2,
                y: container.maxY - margin - menuSize.height
            )
        }
        let x = min(
            max(anchor.midX - menuSize.width / 2, container.minX + margin),
            container.maxX - margin - menuSize.width
        )
        let yAbove = anchor.minY - gap - menuSize.height
        if yAbove >= container.minY + margin {
            return CGPoint(x: x, y: yAbove)
        }
        let yBelow = anchor.maxY + gap
        if yBelow + menuSize.height <= container.maxY - margin {
            return CGPoint(x: x, y: yBelow)
        }
        return CGPoint(x: x, y: max(yAbove, container.minY + margin))
    }

    /// Screen regions occupied by the system text-selection handles around
    /// `selection` (start handle above the leading edge, end handle below the
    /// trailing edge, plus the iOS 17 grabber dots).
    ///
    /// A full-screen tap catcher shown while the selection toolbar is open
    /// must let touches pass through these zones, otherwise dragging a handle
    /// would hit the catcher and the selection could never be adjusted.
    public static func selectionHandleZones(
        around selection: CGRect,
        container: CGRect,
        reach: CGFloat = 64,
        spread: CGFloat = 40
    ) -> [CGRect] {
        guard selection.width >= 0, selection.height >= 0 else { return [] }
        let start = CGRect(
            x: selection.minX - spread,
            y: selection.minY - reach,
            width: spread * 2,
            height: reach + 16
        )
        let end = CGRect(
            x: selection.maxX - spread,
            y: selection.maxY - 16,
            width: spread * 2,
            height: reach + 16
        )
        return [start, end]
            .map { $0.intersection(container) }
            .filter { !$0.isNull && $0.width > 1 && $0.height > 1 }
    }
}
