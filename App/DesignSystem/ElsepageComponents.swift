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
                .background(ElsepageTheme.MaterialToken.control, in: Circle())
                .overlay(Circle().stroke(.primary.opacity(0.06)))
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

struct ElsepageBookCover: View {
    let image: UIImage?
    let title: String
    let author: String?
    let seed: Int

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.25, green: 0.29, blue: 0.25), Color(red: 0.39, green: 0.45, blue: 0.38)],
            [Color(red: 0.36, green: 0.22, blue: 0.18), Color(red: 0.57, green: 0.37, blue: 0.30)],
            [Color(red: 0.31, green: 0.29, blue: 0.20), Color(red: 0.49, green: 0.46, blue: 0.34)],
            [Color(red: 0.21, green: 0.28, blue: 0.29), Color(red: 0.38, green: 0.47, blue: 0.47)]
        ]
        return palettes[abs(seed) % palettes.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.64)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
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
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: ElsepageTheme.Radius.small, style: .continuous))
        .shadow(
            color: ElsepageTheme.Shadow.coverColor,
            radius: ElsepageTheme.Shadow.coverRadius,
            y: ElsepageTheme.Shadow.coverY
        )
        .accessibilityHidden(true)
    }
}
