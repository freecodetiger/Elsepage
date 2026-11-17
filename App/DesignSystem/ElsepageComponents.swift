import AppInfrastructure
import SwiftUI
import UIKit

enum ElsepageIconButtonRole: String, CaseIterable, Identifiable {
    case surface
    case plain
    case filled
    case destructive

    var id: String { rawValue }

    var fill: Color {
        switch self {
        case .surface: ElsepageColor.surface
        case .plain: .clear
        case .filled: ElsepageColor.accent
        case .destructive: ElsepageColor.danger
        }
    }

    var foreground: Color {
        switch self {
        case .surface, .plain: ElsepageColor.textPrimary
        case .filled, .destructive: ElsepageColor.onAccent
        }
    }

    var hasBorder: Bool { self == .surface }
}

/// Circular icon button used in the reader chrome and onboarding header.
/// A11Y-01: the frame scales with Dynamic Type (@ScaledMetric) so the touch
/// target keeps up with the icon; A11Y-03: the base is the 44pt HIG minimum.
struct ElsepageIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var role: ElsepageIconButtonRole
    var isEnabled: Bool
    var isLoading: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = AccessibilityMetrics.minimumTapTargetSide

    init(
        systemName: String,
        accessibilityLabel: String,
        role: ElsepageIconButtonRole = .surface,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(role.foreground)
                } else {
                    Image(systemName: systemName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(role.foreground)
                }
            }
            .frame(width: side, height: side)
            .background(role.fill, in: Circle())
            .overlay {
                if role.hasBorder {
                    Circle().stroke(ElsepageColor.border, lineWidth: ElsepageBorder.hairline)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? (isLoading ? ElsepageState.loadingOpacity : 1) : ElsepageState.disabledOpacity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isLoading ? "加载中" : "")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    private var titleFont: Font {
        // A 120pt grid cover leaves ~98pt of label width; 17pt serif broke
        // "Foundation" mid-word ("Foundatio / n"). Scale with the cover so
        // the placeholder wraps at word boundaries on the smallest covers.
        let size = min(17, max(12, width * 0.13))
        return .system(size: size, weight: .semibold, design: .serif)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: ElsepageTheme.Spacing.xSmall) {
            Text(title)
                .font(titleFont)
                .lineLimit(3)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
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
            // The generated cover label is decorative repetition of the title
            // below it. At accessibility sizes it cannot fit the fixed 2:3 box
            // and breaks mid-word, so leave the gradient artwork alone.
            if image == nil, !dynamicTypeSize.isAccessibilitySize { label }
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




/// The top row shared by 书架 / 想法 / 我的: the large title and the trailing
/// glass capsule on one line. The title no longer sits in a second row below
/// the toolbar; the content starts below the search field (if any).
struct ElsepageRootHeader<Actions: View>: View {
    let title: String
    let actions: Actions

    init(title: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.elsepageTextPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                actions
            }
            .frame(height: 44)
            .elsepageHeaderGlass()
        }
        .padding(.horizontal, ElsepageTheme.Spacing.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// The native-looking search field used below the header. The system
/// `.searchable` bar is tied to the navigation bar, so the custom header owns
/// this field instead.
struct ElsepageSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.elsepageTextSecondary)
            TextField(
                "",
                text: $text,
                prompt: Text(prompt).foregroundStyle(Color.elsepageTextSecondary)
            )
            .font(.body)
            .foregroundStyle(Color.elsepageTextPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFocused)
            .onSubmit { isFocused = false }
            .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.elsepageTextTertiary)
                        // The glyph was a 16pt tap target; the row is the
                        // control and the clear action gets the full 44pt.
                        .frame(width: ElsepageSpacing.touchTarget, height: ElsepageSpacing.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: ElsepageSpacing.fieldMinHeight)
        .background(
            Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct HeaderGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.elsepageSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.elsepageBorder, lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.elsepageBorder.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
        }
    }
}

private extension View {
    func elsepageHeaderGlass() -> some View {
        modifier(HeaderGlass())
    }
}
