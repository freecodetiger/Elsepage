import SwiftUI
import UIKit

struct ElsepageIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(ElsepageTheme.MaterialToken.control, in: Circle())
                .overlay(Circle().stroke(.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
                if let author, !author.isEmpty {
                    Text(author).font(ElsepageTheme.Typography.metadata).opacity(0.72).lineLimit(2)
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
