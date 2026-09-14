import AppInfrastructure
import LibraryCore
import SwiftUI
import UIKit

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case spines
    case covers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .spines: "书脊"
        case .covers: "封面"
        }
    }
}

enum LibraryBookMetrics {
    /// A cover and a spine are different faces of the same physical object.
    /// Keeping one shared height prevents the desk hero from looking like a
    /// differently scaled copy of the books below it.
    static let objectHeight: CGFloat = 150
    static let currentCoverWidth: CGFloat = 100
    static let spineWidth: CGFloat = 36
    static let spineTapTarget: CGFloat = 44
}

enum LibraryShelfPalette {
    private static let colors: [Color] = [
        Color(red: 0.66, green: 0.36, blue: 0.27),
        Color(red: 0.31, green: 0.43, blue: 0.52),
        Color(red: 0.61, green: 0.49, blue: 0.25),
        Color(red: 0.38, green: 0.50, blue: 0.37),
        Color(red: 0.43, green: 0.36, blue: 0.53),
        Color(red: 0.64, green: 0.38, blue: 0.43),
        Color(red: 0.28, green: 0.47, blue: 0.46)
    ]

    static func color(for bookID: BookID) -> Color {
        let uuid = bookID.rawValue.uuid
        let index = Int(uuid.0) % colors.count
        return colors[index]
    }
}

struct LibraryShelfView: View {
    let books: [Book]
    let mode: LibraryDisplayMode
    let cover: (Book) -> UIImage?
    let progress: (Book) -> Double?
    let openBook: (Book) -> Void
    let loadCover: (Book) async -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if mode == .spines && !dynamicTypeSize.isAccessibilitySize {
            LibrarySpineShelf(
                books: books,
                progress: progress,
                openBook: openBook
            )
        } else {
            LibraryCoverShelf(
                books: books,
                cover: cover,
                progress: progress,
                openBook: openBook,
                loadCover: loadCover,
                singleColumn: dynamicTypeSize.isAccessibilitySize
            )
        }
    }
}

private struct LibrarySpineShelf: View {
    let books: [Book]
    let progress: (Book) -> Double?
    let openBook: (Book) -> Void

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: LibraryBookMetrics.spineTapTarget,
                        maximum: 52
                    ),
                    spacing: 18
                )
            ],
            spacing: 28
        ) {
            ForEach(books) { book in
                VStack(spacing: 0) {
                    BookSpineView(
                        book: book,
                        color: LibraryShelfPalette.color(for: book.id),
                        progress: progress(book),
                        openBook: { openBook(book) }
                    )
                    .frame(
                        width: LibraryBookMetrics.spineTapTarget,
                        height: LibraryBookMetrics.objectHeight
                    )

                    Rectangle()
                        .fill(Color.elsepageBorder)
                        .frame(width: LibraryBookMetrics.spineTapTarget, height: 1)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
                }
                .frame(minWidth: LibraryBookMetrics.spineTapTarget)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct BookSpineView: View {
    let book: Book
    let color: Color
    let progress: Double?
    let openBook: () -> Void

    @State private var isPulled = false

    private var verticalTitle: [String] {
        let characters = Array(book.title.prefix(7))
        var result = characters.map(String.init)
        if book.title.count > characters.count {
            result[result.count - 1] = "…"
        }
        return result
    }

    var body: some View {
        Button {
            Haptics.bookPulled()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                isPulled = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                openBook()
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.22), .clear, .black.opacity(0.18)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.20))
                            .frame(width: 1)
                            .padding(.vertical, 5)
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(.black.opacity(0.12))
                            .frame(width: 1)
                            .padding(.vertical, 5)
                    }

                VStack(spacing: 1) {
                    ForEach(Array(verticalTitle.enumerated()), id: \.offset) { _, character in
                        Text(character)
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .foregroundStyle(.white.opacity(0.94))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 10)

                if let progress, progress > 0 {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 3, height: max(8, 108 * progress))
                        .padding(.leading, 7)
                        .padding(.bottom, 8)
                }
            }
            .frame(
                width: LibraryBookMetrics.spineWidth,
                height: LibraryBookMetrics.objectHeight
            )
            .shadow(color: .black.opacity(0.16), radius: isPulled ? 12 : 5, y: isPulled ? 9 : 3)
            .offset(y: isPulled ? -9 : 0)
        }
        .buttonStyle(BookPressButtonStyle())
        .contentShape(Rectangle())
        .accessibilityLabel("《\(book.title)》，\(book.author ?? "未知作者")")
        .accessibilityHint("打开并继续阅读")
    }
}

private struct LibraryCoverShelf: View {
    let books: [Book]
    let cover: (Book) -> UIImage?
    let progress: (Book) -> Double?
    let openBook: (Book) -> Void
    let loadCover: (Book) async -> Void
    let singleColumn: Bool

    private var columns: [GridItem] {
        if singleColumn {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(books) { book in
                Button {
                    Haptics.bookPulled()
                    openBook(book)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        ElsepageBookCover(
                            image: cover(book),
                            title: book.title,
                            author: book.author,
                            seed: Int(book.id.rawValue.uuid.0)
                        )
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .task(id: book.id) { await loadCover(book) }
                        Text(book.title)
                            .font(ElsepageTheme.Typography.itemTitle)
                            .foregroundStyle(Color.elsepageTextPrimary)
                            .lineLimit(2)
                        Text(book.author?.isEmpty == false ? book.author! : "未知作者")
                            .font(ElsepageTheme.Typography.metadata)
                            .foregroundStyle(Color.elsepageTextSecondary)
                            .lineLimit(1)
                        if let progress = progress(book) {
                            ProgressView(value: progress)
                                .tint(LibraryShelfPalette.color(for: book.id))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BookPressButtonStyle())
                .accessibilityLabel("《\(book.title)》，\(book.author ?? "未知作者")")
                .accessibilityHint("打开并继续阅读")
            }
        }
    }
}

private struct BookPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? -2 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
