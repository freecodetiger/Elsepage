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

enum LibraryWoodSurfaceKind {
    case desk
    case shelf
}

/// Low-contrast procedural walnut. It keeps the furniture feeling physical
/// without shipping texture images or turning the whole app into skeuomorphism.
struct LibraryWoodSurface: View {
    let kind: LibraryWoodSurfaceKind
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = woodColors
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    colors: [colors.top, colors.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Canvas { context, size in
                    let lineCount = max(kind == .desk ? 10 : 4, Int(size.height / 13))
                    for index in 0..<lineCount {
                        let ratio = (CGFloat(index) + 0.5) / CGFloat(lineCount)
                        let y = size.height * ratio
                        let bend = CGFloat((index % 5) - 2) * 0.7
                        var grain = Path()
                        grain.move(to: CGPoint(x: -12, y: y))
                        grain.addCurve(
                            to: CGPoint(x: size.width + 12, y: y - bend),
                            control1: CGPoint(x: size.width * 0.24, y: y + bend - 1.5),
                            control2: CGPoint(x: size.width * 0.76, y: y - bend + 1.5)
                        )
                        context.stroke(
                            grain,
                            with: .color(colors.grain.opacity(index.isMultiple(of: 4) ? 0.9 : 0.55)),
                            lineWidth: index.isMultiple(of: 4) ? 0.8 : 0.45
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(kind == .desk ? 0.10 : 0.08),
                        .clear,
                        Color.black.opacity(kind == .desk ? 0.12 : 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                shape.stroke(colors.highlight, lineWidth: 0.7)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, colors.edge],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: kind == .desk ? 12 : 6)
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.34 : (kind == .desk ? 0.22 : 0.17)),
                radius: kind == .desk ? 14 : 5,
                y: kind == .desk ? 8 : 3
            )
    }

    private var woodColors: (
        top: Color,
        bottom: Color,
        grain: Color,
        edge: Color,
        highlight: Color
    ) {
        if colorScheme == .dark {
            return (
                Color(red: 0.27, green: 0.15, blue: 0.085),
                Color(red: 0.14, green: 0.075, blue: 0.04),
                .black.opacity(0.34),
                .black.opacity(0.42),
                .white.opacity(0.09)
            )
        }

        return (
            Color(red: 0.51, green: 0.32, blue: 0.18),
            Color(red: 0.34, green: 0.19, blue: 0.10),
            .black.opacity(0.20),
            .black.opacity(0.28),
            .white.opacity(0.20)
        )
    }
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
    let transitionNamespace: Namespace.ID
    let openBook: (Book) -> Void
    let loadCover: (Book) async -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if mode == .spines && !dynamicTypeSize.isAccessibilitySize {
            LibrarySpineShelf(
                books: books,
                progress: progress,
                transitionNamespace: transitionNamespace,
                openBook: openBook
            )
        } else {
            LibraryCoverShelf(
                books: books,
                cover: cover,
                progress: progress,
                transitionNamespace: transitionNamespace,
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
    let transitionNamespace: Namespace.ID
    let openBook: (Book) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            shelfRows(columns: 6)
            shelfRows(columns: 5)
            shelfRows(columns: 4)
            shelfRows(columns: 3)
            shelfRows(columns: 2)
            shelfRows(columns: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func shelfRows(columns: Int) -> some View {
        let spacing: CGFloat = 14
        let rowWidth = CGFloat(columns) * LibraryBookMetrics.spineTapTarget
            + CGFloat(max(columns - 1, 0)) * spacing

        return VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(stride(from: 0, to: books.count, by: columns)), id: \.self) { start in
                let rowBooks = Array(books[start..<min(start + columns, books.count)])

                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(rowBooks) { book in
                            BookSpineView(
                                book: book,
                                color: LibraryShelfPalette.color(for: book.id),
                                progress: progress(book),
                                transitionNamespace: transitionNamespace,
                                openBook: { openBook(book) }
                            )
                            .frame(
                                width: LibraryBookMetrics.spineTapTarget,
                                height: LibraryBookMetrics.objectHeight
                            )
                        }
                    }
                    .frame(width: rowWidth, alignment: .leading)

                    LibraryWoodSurface(kind: .shelf, cornerRadius: 4)
                        .frame(width: rowWidth, height: 16)
                }
                .frame(width: rowWidth, alignment: .leading)
                .accessibilityElement(children: .contain)
            }
        }
        .frame(width: rowWidth, alignment: .leading)
    }
}

private struct BookSpineView: View {
    let book: Book
    let color: Color
    let progress: Double?
    let transitionNamespace: Namespace.ID
    let openBook: () -> Void

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
            openBook()
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
            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
        }
        .buttonStyle(BookPressButtonStyle())
        .contentShape(Rectangle())
        .matchedTransitionSource(id: book.id, in: transitionNamespace)
        .accessibilityLabel("《\(book.title)》，\(book.author ?? "未知作者")")
        .accessibilityHint("打开并继续阅读")
    }
}

private struct LibraryCoverShelf: View {
    let books: [Book]
    let cover: (Book) -> UIImage?
    let progress: (Book) -> Double?
    let transitionNamespace: Namespace.ID
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
                        .matchedTransitionSource(id: book.id, in: transitionNamespace)
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
