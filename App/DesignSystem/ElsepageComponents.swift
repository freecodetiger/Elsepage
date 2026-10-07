import AppInfrastructure
import SwiftUI
import UIKit

/// Circular icon button used in the reader chrome and onboarding header.
/// A11Y-01: the frame scales with Dynamic Type (@ScaledMetric) so the touch
/// target keeps up with the icon; A11Y-03: the base is the 44pt HIG minimum.
struct ElsepageIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = AccessibilityMetrics.minimumTapTargetSide

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: side, height: side)
                .background(Color.elsepageSurface, in: Circle())
                .overlay(Circle().stroke(Color.elsepageBorder))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    /// A11Y-03: expands the hit-tested area to at least the 44×44pt HIG minimum
    /// without changing what is drawn. Apply to plain-style icon buttons whose
    /// visual glyph is smaller than the minimum target.
    func elsepageTapTarget() -> some View {
        frame(
            minWidth: AccessibilityMetrics.minimumTapTargetSide,
            minHeight: AccessibilityMetrics.minimumTapTargetSide
        )
        .contentShape(Rectangle())
    }
}

enum ElsepageBookCoverMetrics {
    static let width: CGFloat = 100
    static let height: CGFloat = 150
    /// Covers are always 2:3, regardless of the artwork's own aspect.
    static let aspectRatio: CGFloat = 2 / 3
    static let cornerRadius = ElsepageTheme.Radius.small
    static let shadowColor = ElsepageTheme.Shadow.coverColor
    static let shadowRadius = ElsepageTheme.Shadow.coverRadius
    static let shadowY = ElsepageTheme.Shadow.coverY
}

struct ElsepageBookCover: View {
    let image: UIImage?
    let title: String
    let author: String?
    let seed: Int
    let showsShadow: Bool
    /// Rendered width; height always follows the 2:3 cover ratio. It is passed
    /// in rather than negotiated because a resizable `Image` reports its own
    /// pixel size as its ideal size — so a cover that is allowed to size itself
    /// inside a flexible grid cell comes out wider than the column, and
    /// `scaledToFill` then leaves the artwork sitting short in its own box.
    let width: CGFloat

    init(
        image: UIImage?,
        title: String,
        author: String?,
        seed: Int,
        showsShadow: Bool = true,
        width: CGFloat
    ) {
        self.image = image
        self.title = title
        self.author = author
        self.seed = seed
        self.showsShadow = showsShadow
        self.width = width
    }

    private var size: CGSize {
        CGSize(width: width, height: width / ElsepageBookCoverMetrics.aspectRatio)
    }

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.25, green: 0.29, blue: 0.25), Color(red: 0.39, green: 0.45, blue: 0.38)],
            [Color(red: 0.36, green: 0.22, blue: 0.18), Color(red: 0.57, green: 0.37, blue: 0.30)],
            [Color(red: 0.31, green: 0.29, blue: 0.20), Color(red: 0.49, green: 0.46, blue: 0.34)],
            [Color(red: 0.21, green: 0.28, blue: 0.29), Color(red: 0.38, green: 0.47, blue: 0.47)]
        ]
        return palettes[abs(seed) % palettes.count]
    }

    /// A real cover already carries its own title and artwork; stamping the EPUB
    /// metadata over it only fights the art (titles are frequently a concatenated
    /// multi-book string). The label is reserved for the generated placeholder.
    private var label: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) {
            Text(title)
                .font(ElsepageTheme.Typography.bookTitle)
                .lineLimit(4)
                // The cover frame is fixed 2:3 while the title follows Dynamic
                // Type; graceful downscale keeps oversized type inside the
                // artwork instead of clipping it (A11Y-01). The card's real
                // title text below the cover always renders at full size.
                .minimumScaleFactor(0.5)
            if let author, !author.isEmpty {
                Text(author)
                    .font(ElsepageTheme.Typography.metadata)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .opacity(0.72)
            }
        }
        .foregroundStyle(.white)
        .padding(ElsepageTheme.Spacing.medium)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        // The canonical fill recipe, with every size stated explicitly. Nothing
        // here negotiates with the parent: the artwork gets the full 2:3 box and
        // is clipped to it, and the label rides in a bottom-leading overlay that
        // cannot change the box either.
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(width: size.width, height: size.height)
                .clipped()
            if image == nil { label }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: ElsepageBookCoverMetrics.cornerRadius, style: .continuous)
        )
        .shadow(
            color: showsShadow ? ElsepageBookCoverMetrics.shadowColor : .clear,
            radius: showsShadow ? ElsepageBookCoverMetrics.shadowRadius : 0,
            y: showsShadow ? ElsepageBookCoverMetrics.shadowY : 0
        )
        .accessibilityHidden(true)
    }
}
