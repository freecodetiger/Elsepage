import AppInfrastructure
import LibraryCore
import SwiftUI
import UIKit

/// The library's cover grid. Covers are the primary object: no spine metaphor,
/// no per-book decorative colour, no separate hero card above the grid. The one
/// card carrying state — the book you are reading, or one whose session is
/// waiting for a reflection — says so in a single quiet line.
struct LibraryGridView: View {
    let books: [Book]
    let cover: (Book) -> UIImage?
    let progress: (Book) -> Double?
    /// The quiet third line ("第 3 章", "读过 24 分钟 · 划线 3"), or nil to leave
    /// the slot empty.
    let statusLine: (Book) -> String?
    /// The book whose session awaits a reflection; its status line is replaced
    /// by the 补写想法 affordance.
    let pendingReflectionBookID: BookID?
    let transitionNamespace: Namespace.ID
    let openBook: (Book) -> Void
    let loadCover: (Book) async -> Void
    let writeReflection: (Book) -> Void
    let requestDelete: (Book) -> Void
    let accessibilityLabel: (Book) -> String
    /// The width the grid may use. Covers are given an explicit size rather than
    /// a flexible one, so the grid needs to know it up front — see
    /// `ElsepageBookCover.width`.
    let containerWidth: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A fixed three columns, not `.adaptive`: adaptive negotiates the item
    /// width against the content's own sizing and settles wider than its
    /// `maximum`, which drops the grid to two oversized columns. Three equal
    /// flexible columns are deterministic — 110pt covers on a 402pt screen,
    /// 101pt on a 375pt one.
    private var columns: [GridItem] {
        // A11Y-01: covers this small are unreadable at accessibility sizes; one
        // full-width column keeps the title legible instead of squeezed.
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: ElsepageTheme.Spacing.medium),
            count: 3
        )
    }

    /// Exactly the column width, so each cover fills its cell edge to edge.
    private var coverWidth: CGFloat {
        let usable = containerWidth - ElsepageTheme.Spacing.page * 2
        guard !dynamicTypeSize.isAccessibilitySize else { return usable }
        return (usable - ElsepageTheme.Spacing.medium * 2) / 3
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: ElsepageTheme.Spacing.large) {
            ForEach(books) { book in
                card(book)
            }
        }
        .padding(ElsepageTheme.Spacing.page)
    }

    private func card(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.small) {
            Button {
                Haptics.bookPulled()
                openBook(book)
            } label: {
                VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) {
                    coverArt(book)
                    if let progress = progress(book), progress > 0 {
                        ProgressView(value: progress)
                            .tint(.elsepageInteractive)
                    }
                    Text(book.title)
                        .font(ElsepageTheme.Typography.itemTitle)
                        .foregroundStyle(Color.elsepageTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(authorName(book))
                        .font(ElsepageTheme.Typography.metadata)
                        .foregroundStyle(Color.elsepageTextSecondary)
                        .lineLimit(1)
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

            // A sibling of the cover button, never nested inside it, so opening
            // the book and writing the reflection keep separate hit targets.
            if pendingReflectionBookID == book.id {
                Button("补写想法") { writeReflection(book) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.elsepageInteractive)
                    .foregroundStyle(Color.elsepageOnInteractive)
            } else if let line = statusLine(book) {
                Text(line)
                    .font(ElsepageTheme.Typography.metadata)
                    .foregroundStyle(Color.elsepageTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
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
