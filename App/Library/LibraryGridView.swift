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
    let transitionNamespace: Namespace.ID
    let openBook: (Book) -> Void
    let loadCover: (Book) async -> Void
    let requestDelete: (Book) -> Void
    let accessibilityLabel: (Book) -> String
    /// The width the grid may use. Covers are given an explicit size rather than
    /// a flexible one, so the grid needs to know it up front — see
    /// `ElsepageBookCover.width`.
    let containerWidth: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        guard !dynamicTypeSize.isAccessibilitySize else { return usable }
        return (usable - columnSpacing * 2) / 3
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(books) { book in
                card(book)
            }
        }
        .padding(.horizontal, pageInset)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private func card(_ book: Book) -> some View {
        Button {
            Haptics.bookPulled()
            openBook(book)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                coverArt(book)
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
        }
        .buttonStyle(BookPressButtonStyle(reduceMotion: reduceMotion))
        .contextMenu {
            Button(role: .destructive) { requestDelete(book) } label: {
                Label("从书架移除", systemImage: "trash")
            }
        }
        .accessibilityLabel(accessibilityLabel(book))
        .accessibilityHint("打开并继续阅读")
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

private struct BookPressButtonStyle: ButtonStyle {
    /// Passed in rather than read from the environment: Reduce Motion must
    /// suppress the press animation entirely (`.moment` returns nil).
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ElsepageTheme.Motion.moment(reduceMotion), value: configuration.isPressed)
    }
}
