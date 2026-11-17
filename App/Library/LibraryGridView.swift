import AppInfrastructure
import LibraryCore
import SwiftUI
import UIKit

/// The library's cover grid. Covers are the primary object: no spine metaphor,
/// no per-book decorative colour, no hero card. The book on the desk and its
/// progress live in the current-reading row above the grid; a grid cell carries
/// only the cover, title and author.
struct LibraryGridView: View {
    let books: [Book]
    let cover: (Book) -> UIImage?
    let progress: (Book) -> Double?
    let transitionNamespace: Namespace.ID
    let openBook: (Book) -> Void
    let loadCover: (Book) async -> Void
    let requestDelete: (Book) -> Void
    /// Exchanges two shelf positions; the rest of the grid does not shift.
    let onSwap: (BookID, BookID) -> Void
    /// Reports whether a cover is lifted, so the shell can offer its delete
    /// target for the duration of the drag.
    let onDragChange: (Bool) -> Void
    /// The shell's delete target in window coordinates; `.zero` while absent.
    let trashZone: CGRect
    /// One-step move for VoiceOver, which cannot drag.
    let moveBook: (Book, Int) -> Void
    let accessibilityLabel: (Book) -> String
    /// The width the grid may use. Covers are given an explicit size rather than
    /// a flexible one, so the grid needs to know it up front — see
    /// `ElsepageBookCover.width`.
    let containerWidth: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cellFrames: [BookID: CGRect] = [:]
    @State private var draggedID: BookID?
    @State private var dragPoint: CGPoint?
    /// The grid's own frame, so the finger's window position can place the
    /// floating cover.
    @State private var gridFrame: CGRect = .zero
    /// A lifted cover also receives the touch-up as a tap; a drag is not a tap.
    @State private var suppressTapUntil = Date.distantPast

    private let pageInset: CGFloat = 16
    private let columnSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 24

    /// A fixed three columns, not `.adaptive`: adaptive negotiates the item
    /// width against the content's own sizing and settles wider than its
    /// `maximum`, which drops the grid to two oversized columns. Three equal
    /// flexible columns are deterministic — 112pt covers on a 393pt screen.
    private var columns: [GridItem] {
        // A11Y-01: covers this small are unreadable at accessibility sizes; one
        // full-width column keeps the title legible instead of squeezed.
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing),
            count: 3
        )
    }

    /// Exactly the column width, so each cover fills its cell edge to edge.
    private var coverWidth: CGFloat {
        let usable = containerWidth - pageInset * 2
        // A full-width cover at accessibility sizes becomes a 550pt-tall block
        // and pushes the title below the fold. Cap it and let the row title use
        // the full width instead.
        guard !dynamicTypeSize.isAccessibilitySize else { return min(usable, 180) }
        return (usable - columnSpacing * 2) / 3
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(books) { book in
                card(book)
            }
        }
        .onPreferenceChange(CellFramesKey.self) { frames in
            // Frozen while a drag is live: the preview moves cells, and their
            // moved frames must not feed back into the drop hit test.
            guard draggedID == nil else { return }
            cellFrames = frames
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: books.map(\.id))
        .onChange(of: dropTargetID) { _, target in
            if target != nil { Haptics.selectionChanged() }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { gridFrame = $0 }
        .background(
            ShelfDragBridge(
                onBegan: dragBegan,
                onChanged: { point in dragPoint = point },
                onEnded: dragEnded,
                onCancelled: resetDrag
            )
        )
        .overlay(alignment: .topLeading) {
            if let book = draggedBook, let dragPoint {
                dragPreview(book)
                    .position(
                        x: dragPoint.x - gridFrame.minX,
                        // Carried from its bottom edge: the finger sits at the
                        // cover's lower edge, so the book being hovered stays
                        // visible instead of hiding under the one in hand.
                        y: dragPoint.y - gridFrame.minY - coverWidth * 0.62
                    )
            }
        }
        .padding(.horizontal, pageInset)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private var draggedBook: Book? {
        guard let draggedID else { return nil }
        return books.first { $0.id == draggedID }
    }

    /// The cover follows the finger while it is lifted. Without it the only
    /// feedback was a dimmed cell, which reads as "something is off", not as
    /// "I am holding this book".
    private func dragPreview(_ book: Book) -> some View {
        ElsepageBookCover(
            image: cover(book),
            title: book.title,
            author: book.author,
            seed: Int(book.id.rawValue.uuid.0),
            showsShadow: false,
            width: coverWidth
        )
        // Two short shadows, both bounded by the cover: a contact edge that
        // keeps the corners crisp and a slightly softer one for lift. A single
        // long shadow smeared past the cover onto the rows underneath it.
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(
            color: .black.opacity(0.22),
            radius: ElsepageBookCoverMetrics.shadowRadius * 1.4,
            y: ElsepageBookCoverMetrics.shadowY * 1.2
        )
        .scaleEffect(1.06)
        .rotationEffect(.degrees(2))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// The cover follows the finger, so the source cell recedes into an empty
    /// slot instead of growing: two lifts at once read as a glitch.
    private func card(_ book: Book) -> some View {
        cell(book)
            .scaleEffect(draggedID == book.id ? 0.96 : 1)
            .opacity(draggedID == book.id ? 0 : 1)
            .background {
                // The slot left behind stays as a quiet well rather than a
                // ghosted copy of the cover and its text.
                if draggedID == book.id {
                    VStack(spacing: 8) {
                        RoundedRectangle(
                            cornerRadius: ElsepageBookCoverMetrics.cornerRadius,
                            style: .continuous
                        )
                        .fill(Color.elsepageInteractive.opacity(0.07))
                        .frame(width: coverWidth)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(ElsepageTheme.Motion.moment(reduceMotion), value: draggedID)
            // The hovered book slides into the slot the dragged one left. That
            // preview is the drop feedback: an outline would sit under the
            // carried cover and never be seen.
            .offset(swapPreviewOffset(book))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: dropTargetID)
            .onTapGesture {
                guard Date() >= suppressTapUntil else { return }
                Haptics.bookPulled()
                openBook(book)
            }
            .accessibilityAction(named: "移除这本书") { requestDelete(book) }
            .accessibilityAction(named: "上移一位") { moveBook(book, -1) }
            .accessibilityAction(named: "下移一位") { moveBook(book, 1) }
    }

    private func swapPreviewOffset(_ book: Book) -> CGSize {
        guard dropTargetID == book.id,
              let draggedID,
              let target = cellFrames[book.id],
              let source = cellFrames[draggedID] else { return .zero }
        return CGSize(width: source.midX - target.midX, height: source.midY - target.midY)
    }

    private var dropTargetID: BookID? {
        guard let draggedID, let dragPoint else { return nil }
        return cellFrames.first { $0.key != draggedID && $0.value.contains(dragPoint) }?.key
    }

    /// Reordering is driven by one UIKit long press on the scroll view, not by
    /// a SwiftUI gesture per cover: a `DragGesture` placed on the cells either
    /// swallows the shelf's scrolling or loses the touch to it. A recognizer
    /// fails on movement, so scrolling and taps are untouched, and it tracks
    /// the finger itself once the hold completes.
    private func dragBegan(at point: CGPoint) -> Bool {
        guard let id = cellFrames.first(where: { $0.value.contains(point) })?.key,
              let book = books.first(where: { $0.id == id }) else { return false }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
            draggedID = book.id
            dragPoint = point
        }
        suppressTapUntil = .distantFuture
        Haptics.bookPulled()
        onDragChange(true)
        return true
    }

    private func dragEnded(at point: CGPoint) {
        defer { resetDrag() }
        guard let draggedID else { return }
        // The delete target sits in the shell's bar, outside this view.
        if trashZone != .zero, trashZone.insetBy(dx: -12, dy: -12).contains(point) {
            guard let book = books.first(where: { $0.id == draggedID }) else { return }
            requestDelete(book)
            return
        }
        guard let target = cellFrames.first(where: { $0.key != draggedID && $0.value.contains(point) })?.key else {
            return
        }
        onSwap(draggedID, target)
    }

    private func resetDrag() {
        if draggedID != nil {
            // The cell's tap also receives the touch-up; a lift is not a tap.
            suppressTapUntil = Date().addingTimeInterval(0.5)
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            draggedID = nil
            dragPoint = nil
        }
        onDragChange(false)
    }

    /// A plain view with an explicit button trait rather than a `Button`: the
    /// cell is the target of a long-press recognizer, and the tap is handled by
    /// the card so the two cannot starve each other.
    private func cell(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                coverArt(book)

                // A quiet "where was I" cue for every other book. The
                // current book owns the full progress row above; this is
                // only a 2pt line, not a third text line.
                if let progress = progress(book), progress > 0 {
                    ProgressView(value: progress)
                        .tint(.elsepageInteractive)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.elsepageTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(authorName(book))
                    .font(.footnote)
                    .foregroundStyle(Color.elsepageTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CellFramesKey.self,
                    value: [book.id: proxy.frame(in: .global)]
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel(book))
        .accessibilityHint("打开并继续阅读；长按拖动换位")
        .accessibilityAction {
            Haptics.bookPulled()
            openBook(book)
        }
    }

    private func coverArt(_ book: Book) -> some View {
        ElsepageBookCover(
            image: cover(book),
            title: book.title,
            author: book.author,
            seed: Int(book.id.rawValue.uuid.0),
            // The zoom source below draws the cover shadow; letting the cover
            // draw its own as well stacked two shadows at different radii.
            showsShadow: false,
            width: coverWidth
        )
        .matchedTransitionSource(id: book.id, in: transitionNamespace) { source in
            source
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ElsepageBookCoverMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .shadow(
                    color: ElsepageBookCoverMetrics.shadowColor,
                    radius: ElsepageBookCoverMetrics.shadowRadius,
                    y: ElsepageBookCoverMetrics.shadowY
                )
        }
        .task(id: book.id) { await loadCover(book) }
    }

    private func authorName(_ book: Book) -> String {
        guard let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else { return "未知作者" }
        return author
    }
}

/// A single long press installed on the shelf's scroll view. UIKit recognizers
/// compose with a scroll view's pan the way SwiftUI gestures do not: the hold
/// fails as soon as the finger moves, so the shelf scrolls normally.
private struct ShelfDragBridge: UIViewRepresentable {
    let onBegan: (CGPoint) -> Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(from: uiView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ShelfDragBridge
        private weak var scrollView: UIScrollView?
        private var isDragging = false

        init(_ parent: ShelfDragBridge) {
            self.parent = parent
        }

        /// The recognizer has to sit on the scroll view: only an ancestor of
        /// the covers receives their touches.
        func attach(from view: UIView) {
            guard let scrollView = view.enclosingScrollView, self.scrollView !== scrollView else { return }
            self.scrollView = scrollView
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handle))
            recognizer.minimumPressDuration = 0.35
            recognizer.allowableMovement = 6
            // The cell's tap must still run for a short press; a completed
            // drag suppresses it in SwiftUI instead.
            recognizer.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(recognizer)
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: nil)
            switch recognizer.state {
            case .began:
                isDragging = parent.onBegan(point)
                // Hand the touch over: the shelf must not scroll under a lifted cover.
                if isDragging { scrollView?.panGestureRecognizer.isEnabled = false }
            case .changed:
                if isDragging { parent.onChanged(point) }
            case .ended:
                if isDragging { parent.onEnded(point) }
                finish()
            default:
                if isDragging { parent.onCancelled() }
                finish()
            }
        }

        private func finish() {
            isDragging = false
            scrollView?.panGestureRecognizer.isEnabled = true
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }
}

/// Cell frames in the window's coordinate space, used to resolve the book the
/// drag was dropped on. They share the space of the shell's delete target.
private struct CellFramesKey: PreferenceKey {
    static let defaultValue: [BookID: CGRect] = [:]
    static func reduce(value: inout [BookID: CGRect], nextValue: () -> [BookID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
