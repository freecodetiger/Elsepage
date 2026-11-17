import SwiftUI
import UIKit

// MARK: - Button

enum ElsepageButtonRole: String, CaseIterable, Identifiable {
    case primary
    case secondary
    case destructive
    case quiet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .destructive: "Destructive"
        case .quiet: "Quiet"
        }
    }

    var background: Color {
        switch self {
        case .primary: ElsepageColor.accent
        case .secondary: ElsepageColor.surface
        case .destructive: ElsepageColor.danger
        case .quiet: .clear
        }
    }

    var foreground: Color {
        switch self {
        case .primary, .destructive: ElsepageColor.onAccent
        case .secondary: ElsepageColor.textPrimary
        case .quiet: ElsepageColor.accent
        }
    }

    var hasBorder: Bool { self == .secondary }
}

enum ElsepageButtonSize: String, CaseIterable, Identifiable {
    case regular
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "Regular"
        case .compact: "Compact"
        }
    }

    var font: Font {
        switch self {
        case .regular: .system(.body, weight: .semibold)
        case .compact: .system(.subheadline, weight: .semibold)
        }
    }

    var height: CGFloat {
        switch self {
        case .regular: ElsepageSpacing.buttonHeight
        case .compact: ElsepageSpacing.compactButtonHeight
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: ElsepageSpacing.xl
        case .compact: ElsepageSpacing.md
        }
    }
}

/// A styled `Button`. It deliberately keeps `Button` as the interaction owner;
/// the design system only supplies appearance, loading, and disabled states.
struct ElsepageButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ElsepageButtonRole = .primary
    var size: ElsepageButtonSize = .regular
    var isLoading = false
    var isEnabled = true
    var isFullWidth = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: ElsepageSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(role.foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(size.font)
                }
                Text(title)
            }
        }
        .buttonStyle(
            ElsepageButtonStyle(
                role: role,
                size: size,
                isLoading: isLoading,
                isFullWidth: isFullWidth,
                reduceMotion: reduceMotion
            )
        )
        .disabled(!isEnabled || isLoading)
        .accessibilityValue(isLoading ? "加载中" : "")
    }
}

struct ElsepageButtonStyle: ButtonStyle {
    let role: ElsepageButtonRole
    let size: ElsepageButtonSize
    let isLoading: Bool
    let isFullWidth: Bool
    let reduceMotion: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ElsepageButtonChrome(
            role: role,
            size: size,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            isLoading: isLoading,
            isFullWidth: isFullWidth
        ) {
            configuration.label
        }
        .scaleEffect(configuration.isPressed && !reduceMotion ? ElsepageMotion.pressScale : 1)
        .animation(ElsepageMotion.interactive(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The visual half of `ElsepageButton`. The catalog uses it directly to show a
/// pressed state without trying to synthesize a `ButtonStyle.Configuration`.
struct ElsepageButtonChrome<Content: View>: View {
    let role: ElsepageButtonRole
    let size: ElsepageButtonSize
    let isPressed: Bool
    let isEnabled: Bool
    let isLoading: Bool
    let isFullWidth: Bool
    let content: Content

    init(
        role: ElsepageButtonRole,
        size: ElsepageButtonSize,
        isPressed: Bool,
        isEnabled: Bool,
        isLoading: Bool,
        isFullWidth: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.size = size
        self.isPressed = isPressed
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.isFullWidth = isFullWidth
        self.content = content()
    }

    var body: some View {
        content
            .font(size.font)
            .foregroundStyle(role.foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: size.height)
            .background(
                role.background,
                in: RoundedRectangle(cornerRadius: ElsepageRadius.button, style: .continuous)
            )
            .overlay {
                if role.hasBorder {
                    RoundedRectangle(cornerRadius: ElsepageRadius.button, style: .continuous)
                        .stroke(ElsepageColor.border, lineWidth: ElsepageBorder.regular)
                }
            }
            .overlay {
                if isPressed {
                    RoundedRectangle(cornerRadius: ElsepageRadius.button, style: .continuous)
                        .fill(ElsepageColor.pressedOverlay)
                }
            }
            .opacity(opacity)
            .contentShape(RoundedRectangle(cornerRadius: ElsepageRadius.button, style: .continuous))
    }

    private var opacity: Double {
        if isLoading { return ElsepageState.loadingOpacity }
        if !isEnabled { return ElsepageState.disabledOpacity }
        return isPressed ? ElsepageState.pressedOpacity : 1
    }
}

// MARK: - List row

/// A single-line-first row for grouped content. The row is transparent by
/// design: cards belong to the container, not to every row.
struct ElsepageListRow: View {
    let title: String
    var subtitle: String? = nil
    var metadata: String? = nil
    var systemImage: String? = nil
    var trailingText: String? = nil
    var showsChevron = false
    var isEnabled = true
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(
                ElsepageListRowButtonStyle(
                    isEnabled: isEnabled,
                    reduceMotion: reduceMotion
                )
            )
            .disabled(!isEnabled)
            .accessibilityElement(children: .combine)
            .accessibilityHint("打开详情")
        } else {
            content
                .opacity(isEnabled ? 1 : ElsepageState.disabledOpacity)
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: ElsepageSpacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(ElsepageColor.accent)
                    .frame(width: ElsepageSpacing.xxl)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: ElsepageSpacing.xxs) {
                Text(title)
                    .font(ElsepageFont.headline)
                    .foregroundStyle(ElsepageColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(ElsepageFont.subheadline)
                        .foregroundStyle(ElsepageColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let metadata {
                    Text(metadata)
                        .font(ElsepageFont.footnote)
                        .foregroundStyle(ElsepageColor.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: ElsepageSpacing.xs)
            if let trailingText {
                Text(trailingText)
                    .font(ElsepageFont.footnote)
                    .foregroundStyle(ElsepageColor.textTertiary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(ElsepageFont.caption2.weight(.semibold))
                    .foregroundStyle(ElsepageColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, ElsepageSpacing.lg)
        .padding(.vertical, ElsepageSpacing.md)
        .frame(maxWidth: .infinity, minHeight: ElsepageSpacing.touchTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct ElsepageListRowButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? ElsepageColor.pressedOverlay : .clear,
                in: RoundedRectangle(cornerRadius: ElsepageRadius.sm, style: .continuous)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? ElsepageMotion.pressScale : 1)
            .animation(ElsepageMotion.interactive(reduceMotion: reduceMotion), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : ElsepageState.disabledOpacity)
    }
}

// MARK: - Section header

struct ElsepageSectionHeader: View {
    let title: String
    var count: Int? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ElsepageSpacing.sm) {
            Text(title)
                .font(ElsepageFont.title3)
                .foregroundStyle(ElsepageColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text("\(count)")
                    .font(ElsepageFont.footnote)
                    .foregroundStyle(ElsepageColor.textTertiary)
            }
            Spacer(minLength: ElsepageSpacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(ElsepageFont.subheadline.weight(.semibold))
                    .foregroundStyle(ElsepageColor.accent)
                    .frame(minHeight: ElsepageSpacing.touchTarget)
            }
        }
    }
}

// MARK: - Input

struct ElsepageInput: View {
    let title: String
    @Binding var text: String
    var prompt: String? = nil
    var helper: String? = nil
    var error: String? = nil
    var isSecure = false
    var isEnabled = true
    var textContentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disablesAutocorrection = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageSpacing.xs) {
            Text(title)
                .font(ElsepageFont.footnote.weight(.medium))
                .foregroundStyle(ElsepageColor.textSecondary)
                .accessibilityHidden(true)

            field
                .font(ElsepageFont.body)
                .foregroundStyle(ElsepageColor.textPrimary)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(disablesAutocorrection)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .submitLabel(submitLabel)
                .focused($isFocused)
                .onSubmit { onSubmit?() }
                .padding(.horizontal, ElsepageSpacing.md)
                .frame(minHeight: ElsepageSpacing.fieldMinHeight)
                .background(
                    ElsepageColor.fieldFill,
                    in: RoundedRectangle(cornerRadius: ElsepageRadius.field, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ElsepageRadius.field, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                }
                .accessibilityLabel(title)
                .accessibilityHint(Text(error ?? helper ?? ""))

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(ElsepageFont.caption)
                    .foregroundStyle(ElsepageColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let helper {
                Text(helper)
                    .font(ElsepageFont.caption)
                    .foregroundStyle(ElsepageColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(isEnabled ? 1 : ElsepageState.disabledOpacity)
        .disabled(!isEnabled)
    }

    @ViewBuilder private var field: some View {
        if isSecure {
            SecureField(
                "",
                text: $text,
                prompt: Text(prompt ?? title).foregroundStyle(ElsepageColor.textTertiary)
            )
        } else {
            TextField(
                "",
                text: $text,
                prompt: Text(prompt ?? title).foregroundStyle(ElsepageColor.textTertiary)
            )
        }
    }

    private var borderColor: Color {
        if error != nil { return ElsepageColor.danger }
        if isFocused { return ElsepageColor.accent }
        return ElsepageColor.border
    }

    private var borderWidth: CGFloat {
        isFocused || error != nil ? ElsepageBorder.strong : ElsepageBorder.regular
    }
}

// MARK: - Card

enum ElsepageCardStyle {
    case surface
    case secondary
    case elevated
    case plain

    var fill: Color {
        switch self {
        case .surface, .elevated: ElsepageColor.surface
        case .secondary: ElsepageColor.surfaceSecondary
        case .plain: .clear
        }
    }

    var hasBorder: Bool { self != .plain }
    var shadow: ElsepageShadow {
        switch self {
        case .elevated: ElsepageElevation.card
        case .surface, .secondary, .plain: .none
        }
    }
}

struct ElsepageCard<Content: View>: View {
    var style: ElsepageCardStyle = .surface
    var padding: CGFloat = ElsepageSpacing.lg
    let content: Content

    init(
        style: ElsepageCardStyle = .surface,
        padding: CGFloat = ElsepageSpacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elsepageCardSurface(
                radius: ElsepageRadius.card,
                fill: style.fill,
                border: style.hasBorder,
                elevation: style.shadow
            )
    }
}

// MARK: - Empty / Loading / Error

struct ElsepageEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(ElsepageColor.accent)
            }
        }
    }
}

struct ElsepageLoadingState: View {
    var message = "正在加载…"
    var isFullScreen = false

    var body: some View {
        VStack(spacing: ElsepageSpacing.md) {
            ProgressView()
                .tint(ElsepageColor.accent)
            Text(message)
                .font(ElsepageFont.subheadline)
                .foregroundStyle(ElsepageColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: isFullScreen ? .infinity : nil
        )
        .padding(ElsepageSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct ElsepageErrorState: View {
    let title: String
    var message: String? = nil
    var retryTitle: String = "重试"
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(ElsepageColor.accent)
            }
        }
    }
}

struct ElsepageInlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(ElsepageFont.caption)
            .foregroundStyle(ElsepageColor.danger)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Banner / Toast

enum ElsepageBannerStyle: String, CaseIterable, Identifiable {
    case info
    case success
    case warning
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: "Info"
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var color: Color {
        switch self {
        case .info: ElsepageColor.accent
        case .success: ElsepageColor.success
        case .warning: ElsepageColor.warning
        case .error: ElsepageColor.danger
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

struct ElsepageBanner: View {
    let style: ElsepageBannerStyle
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: ElsepageSpacing.sm) {
            Image(systemName: style.systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(style.color)
                .padding(.top, ElsepageSpacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ElsepageSpacing.xxs) {
                Text(title)
                    .font(ElsepageFont.subheadline.weight(.semibold))
                    .foregroundStyle(ElsepageColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(ElsepageFont.footnote)
                        .foregroundStyle(ElsepageColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(ElsepageFont.footnote.weight(.semibold))
                        .foregroundStyle(style.color)
                        .frame(minHeight: ElsepageSpacing.touchTarget, alignment: .leading)
                }
            }
            Spacer(minLength: ElsepageSpacing.xs)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(ElsepageFont.caption2.weight(.semibold))
                        .foregroundStyle(ElsepageColor.textTertiary)
                        .frame(width: ElsepageSpacing.touchTarget, height: ElsepageSpacing.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
        .padding(ElsepageSpacing.md)
        .background(
            style.color.opacity(0.10),
            in: RoundedRectangle(cornerRadius: ElsepageRadius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ElsepageRadius.md, style: .continuous)
                .stroke(style.color.opacity(0.22), lineWidth: ElsepageBorder.hairline)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ElsepageToast: View {
    let style: ElsepageBannerStyle
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: ElsepageSpacing.sm) {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.color)
                .accessibilityHidden(true)
            Text(message)
                .font(ElsepageFont.subheadline.weight(.medium))
                .foregroundStyle(ElsepageColor.textPrimary)
                .lineLimit(2)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(ElsepageFont.subheadline.weight(.semibold))
                    .foregroundStyle(ElsepageColor.accent)
                    .frame(minHeight: ElsepageSpacing.touchTarget)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(ElsepageFont.caption2.weight(.semibold))
                        .foregroundStyle(ElsepageColor.textTertiary)
                        .frame(width: ElsepageSpacing.touchTarget, height: ElsepageSpacing.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
        .padding(.horizontal, ElsepageSpacing.md)
        .padding(.vertical, ElsepageSpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(ElsepageColor.border, lineWidth: ElsepageBorder.hairline))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}

private struct ElsepageToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    let style: ElsepageBannerStyle
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    ElsepageToast(
                        style: style,
                        message: message,
                        actionTitle: actionTitle,
                        action: action,
                        onDismiss: { isPresented = false }
                    )
                    .padding(.horizontal, ElsepageSpacing.page)
                    .padding(.bottom, ElsepageSpacing.lg)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(ElsepageMotion.standard(reduceMotion: reduceMotion), value: isPresented)
    }
}

extension View {
    func elsepageToast(
        isPresented: Binding<Bool>,
        style: ElsepageBannerStyle,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ElsepageToastModifier(
                isPresented: isPresented,
                style: style,
                message: message,
                actionTitle: actionTitle,
                action: action
            )
        )
    }
}
