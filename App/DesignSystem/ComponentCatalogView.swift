#if DEBUG
import SwiftUI

/// Preview-only catalog for the design system. It is deliberately not wired
/// into a tab: the catalog documents reusable pieces, it is not a product page.
struct ComponentCatalogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ElsepageSpacing.xxxl) {
                header
                colorSection
                typographySection
                spacingSection
                buttonSection
                iconButtonSection
                listRowSection
                sectionHeaderSection
                inputSection
                cardSection
                stateSection
                bannerSection
                toastSection
            }
            .padding(ElsepageSpacing.page)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ElsepageColor.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ElsepageSpacing.sm) {
            Text("ElsePage Design System")
                .font(ElsepageFont.display)
                .foregroundStyle(ElsepageColor.textPrimary)
            Text("Tokens and components for new UI. Existing screens migrate one surface at a time.")
                .font(ElsepageFont.subheadline)
                .foregroundStyle(ElsepageColor.textSecondary)
        }
    }

    private var colorSection: some View {
        catalogSection("Colors") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: ElsepageSpacing.md)],
                alignment: .leading,
                spacing: ElsepageSpacing.md
            ) {
                colorSwatch("Canvas", ElsepageColor.canvas)
                colorSwatch("Surface", ElsepageColor.surface)
                colorSwatch("Surface 2", ElsepageColor.surfaceSecondary)
                colorSwatch("Border", ElsepageColor.border)
                colorSwatch("Text primary", ElsepageColor.textPrimary)
                colorSwatch("Text secondary", ElsepageColor.textSecondary)
                colorSwatch("Text tertiary", ElsepageColor.textTertiary)
                colorSwatch("Accent", ElsepageColor.accent)
                colorSwatch("Success", ElsepageColor.success)
                colorSwatch("Warning", ElsepageColor.warning)
                colorSwatch("Danger", ElsepageColor.danger)
            }
        }
    }

    private func colorSwatch(_ title: String, _ color: Color) -> some View {
        HStack(spacing: ElsepageSpacing.sm) {
            RoundedRectangle(cornerRadius: ElsepageRadius.sm, style: .continuous)
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay {
                    RoundedRectangle(cornerRadius: ElsepageRadius.sm, style: .continuous)
                        .stroke(ElsepageColor.border, lineWidth: ElsepageBorder.hairline)
                }
            Text(title)
                .font(ElsepageFont.footnote)
                .foregroundStyle(ElsepageColor.textSecondary)
                .lineLimit(1)
        }
    }

    private var typographySection: some View {
        catalogSection("Typography") {
            VStack(alignment: .leading, spacing: ElsepageSpacing.sm) {
                typeRow("Display · 34/700", ElsepageFont.display)
                typeRow("Title 1 · 28/600", ElsepageFont.title1)
                typeRow("Title 2 · 22/600", ElsepageFont.title2)
                typeRow("Title 3 · 20/600", ElsepageFont.title3)
                typeRow("Headline · 17/600", ElsepageFont.headline)
                typeRow("Body · 17", ElsepageFont.body)
                typeRow("Subheadline · 15", ElsepageFont.subheadline)
                typeRow("Footnote · 13", ElsepageFont.footnote)
                typeRow("Caption · 12", ElsepageFont.caption)
            }
        }
    }

    private func typeRow(_ label: String, _ font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ElsepageSpacing.md) {
            Text(label)
                .font(ElsepageFont.caption)
                .foregroundStyle(ElsepageColor.textTertiary)
                .frame(width: 120, alignment: .leading)
            Text("页外 · ReadLoop")
                .font(font)
                .foregroundStyle(ElsepageColor.textPrimary)
                .lineLimit(1)
        }
    }

    private var spacingSection: some View {
        catalogSection("Spacing & Radius") {
            VStack(alignment: .leading, spacing: ElsepageSpacing.md) {
                HStack(spacing: ElsepageSpacing.sm) {
                    spacingBar("2", ElsepageSpacing.xxs)
                    spacingBar("4", ElsepageSpacing.xs)
                    spacingBar("8", ElsepageSpacing.sm)
                    spacingBar("12", ElsepageSpacing.md)
                    spacingBar("16", ElsepageSpacing.lg)
                    spacingBar("20", ElsepageSpacing.xl)
                    spacingBar("24", ElsepageSpacing.xxl)
                    spacingBar("32", ElsepageSpacing.xxxl)
                }
                HStack(spacing: ElsepageSpacing.sm) {
                    radiusChip("8", ElsepageRadius.sm)
                    radiusChip("12", ElsepageRadius.md)
                    radiusChip("16", ElsepageRadius.lg)
                    radiusChip("24", ElsepageRadius.xl)
                }
            }
        }
    }

    private func spacingBar(_ label: String, _ value: CGFloat) -> some View {
        VStack(spacing: ElsepageSpacing.xxs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ElsepageColor.accent.opacity(0.24))
                .frame(width: max(4, value), height: 24)
            Text(label).font(ElsepageFont.caption2).foregroundStyle(ElsepageColor.textTertiary)
        }
    }

    private func radiusChip(_ label: String, _ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(ElsepageColor.surface)
            .frame(width: 54, height: 40)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(ElsepageColor.border, lineWidth: ElsepageBorder.hairline)
            }
            .overlay {
                Text(label).font(ElsepageFont.caption2).foregroundStyle(ElsepageColor.textSecondary)
            }
    }

    private var buttonSection: some View {
        catalogSection("Buttons") {
            VStack(alignment: .leading, spacing: ElsepageSpacing.md) {
                ForEach(ElsepageButtonRole.allCases) { role in
                    VStack(alignment: .leading, spacing: ElsepageSpacing.sm) {
                        Text(role.title)
                            .font(ElsepageFont.footnote.weight(.semibold))
                            .foregroundStyle(ElsepageColor.textSecondary)
                        HStack(alignment: .top, spacing: ElsepageSpacing.sm) {
                            ForEach(ElsepageControlState.allCases) { state in
                                VStack(spacing: ElsepageSpacing.xs) {
                                    buttonChrome(role: role, state: state)
                                    Text(state.title)
                                        .font(ElsepageFont.caption2)
                                        .foregroundStyle(ElsepageColor.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                ElsepageButton(
                    title: "Very long button title that should wrap without breaking the layout",
                    systemImage: "bookmark",
                    role: .secondary,
                    action: {}
                )
            }
        }
    }

    private func buttonChrome(role: ElsepageButtonRole, state: ElsepageControlState) -> some View {
        ElsepageButtonChrome(
            role: role,
            size: .compact,
            isPressed: state == .pressed,
            isEnabled: state != .disabled,
            isLoading: state == .loading
        ) {
            HStack(spacing: ElsepageSpacing.sm) {
                if state == .loading {
                    ProgressView().controlSize(.small).tint(role.foreground)
                } else {
                    Image(systemName: "bookmark")
                }
                Text("继续")
            }
        }
    }

    private var iconButtonSection: some View {
        catalogSection("Icon buttons") {
            HStack(spacing: ElsepageSpacing.lg) {
                ElsepageIconButton(systemName: "gearshape", accessibilityLabel: "设置", action: {})
                ElsepageIconButton(systemName: "gearshape", accessibilityLabel: "设置", role: .plain, action: {})
                ElsepageIconButton(systemName: "gearshape", accessibilityLabel: "设置", role: .filled, action: {})
                ElsepageIconButton(systemName: "trash", accessibilityLabel: "删除", role: .destructive, action: {})
                ElsepageIconButton(systemName: "gearshape", accessibilityLabel: "设置", isEnabled: false, action: {})
                ElsepageIconButton(systemName: "gearshape", accessibilityLabel: "设置", isLoading: true, action: {})
            }
        }
    }

    private var listRowSection: some View {
        catalogSection("List row") {
            ElsepageCard(padding: 0) {
                VStack(spacing: 0) {
                    ElsepageListRow(
                        title: "ReadLoop Foundation Fixture",
                        subtitle: "ReadLoop Contributors",
                        metadata: "读到 42% · 12 分钟",
                        systemImage: "book.closed",
                        showsChevron: true,
                        action: {}
                    )
                    Divider().padding(.leading, ElsepageSpacing.lg)
                    ElsepageListRow(
                        title: "A very long row title that wraps onto a second line without truncating the metadata",
                        subtitle: "A long subtitle also wraps, but the row keeps the same rhythm.",
                        metadata: "Metadata stays one line",
                        showsChevron: true,
                        action: {}
                    )
                    Divider().padding(.leading, ElsepageSpacing.lg)
                    ElsepageListRow(
                        title: "Disabled row",
                        subtitle: "No action while offline",
                        trailingText: "离线",
                        isEnabled: false,
                        action: {}
                    )
                }
            }
        }
    }

    private var sectionHeaderSection: some View {
        catalogSection("Section header") {
            VStack(alignment: .leading, spacing: ElsepageSpacing.xl) {
                ElsepageSectionHeader(title: "全部书籍", count: 12, actionTitle: "排序", action: {})
                ElsepageSectionHeader(title: "还没有留下记录")
            }
        }
    }

    private var inputSection: some View {
        catalogSection("Input") {
            InputCatalog()
        }
    }

    private var cardSection: some View {
        catalogSection("Card") {
            HStack(alignment: .top, spacing: ElsepageSpacing.md) {
                ElsepageCard {
                    Text("Surface card")
                        .font(ElsepageFont.headline)
                    Text("The default container.")
                        .font(ElsepageFont.subheadline)
                        .foregroundStyle(ElsepageColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                ElsepageCard(style: .secondary) {
                    Text("Secondary card")
                        .font(ElsepageFont.headline)
                    Text("Nested content.")
                        .font(ElsepageFont.subheadline)
                        .foregroundStyle(ElsepageColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var stateSection: some View {
        catalogSection("States") {
            VStack(alignment: .leading, spacing: ElsepageSpacing.md) {
                ElsepageCard {
                    ElsepageEmptyState(
                        title: "还没有解锁成就",
                        message: "读完并留下想法后，会开始解锁一些有意义的徽章。",
                        systemImage: "rosette"
                    )
                    .frame(minHeight: 180)
                }
                ElsepageCard {
                    ElsepageLoadingState(message: "正在整理你的记录…")
                        .frame(minHeight: 120)
                }
                ElsepageCard {
                    ElsepageErrorState(
                        title: "无法打开本地书库",
                        message: "请检查设备存储空间后重试。",
                        retry: {}
                    )
                    .frame(minHeight: 180)
                }
                ElsepageInlineError(message: "还没有配置可用的模型服务。")
            }
        }
    }

    private var bannerSection: some View {
        catalogSection("Banner") {
            VStack(spacing: ElsepageSpacing.md) {
                ForEach(ElsepageBannerStyle.allCases) { style in
                    ElsepageBanner(
                        style: style,
                        title: style.title,
                        message: "A short explanation of the state.",
                        actionTitle: "查看",
                        action: {},
                        onDismiss: {}
                    )
                }
            }
        }
    }

    private var toastSection: some View {
        catalogSection("Toast") {
            ToastCatalog()
        }
    }

    private func catalogSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ElsepageSpacing.md) {
            ElsepageSectionHeader(title: title)
            content()
        }
    }
}

private struct InputCatalog: View {
    @State private var name = "页外"
    @State private var empty = ""
    @State private var secure = ""
    @State private var errorText = ""
    @State private var disabledText = "不可编辑"

    var body: some View {
        VStack(spacing: ElsepageSpacing.lg) {
            ElsepageInput(
                title: "对话身份",
                text: $name,
                helper: "显示在你的消息旁。"
            )
            ElsepageInput(
                title: "API Key",
                text: $secure,
                prompt: "粘贴 API Key",
                isSecure: true
            )
            ElsepageInput(
                title: "模型名称",
                text: $errorText,
                prompt: "按服务商填写",
                error: "模型名称不能为空。"
            )
            ElsepageInput(
                title: "只读字段",
                text: $disabledText,
                isEnabled: false
            )
            ElsepageInput(
                title: "空状态",
                text: $empty,
                helper: "没有内容时显示提示文字。"
            )
        }
    }
}

private struct ToastCatalog: View {
    @State private var showsToast = true

    var body: some View {
        VStack(alignment: .leading, spacing: ElsepageSpacing.lg) {
            ElsepageButton(title: "显示 Toast", role: .secondary, isFullWidth: false) {
                showsToast = true
            }
            ElsepageToast(
                style: .success,
                message: "已保存到标注",
                actionTitle: "查看",
                action: {},
                onDismiss: { showsToast = false }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ElsepageCard {
                Text("Toast 也提供 View 修饰器，默认贴底显示：")
                    .font(ElsepageFont.footnote)
                    .foregroundStyle(ElsepageColor.textSecondary)
                Text(".elsepageToast(isPresented:style:message:actionTitle:action:)")
                    .font(ElsepageFont.mono)
                    .foregroundStyle(ElsepageColor.textTertiary)
            }
        }
        .elsepageToast(
            isPresented: $showsToast,
            style: .success,
            message: "已保存到标注",
            actionTitle: "查看",
            action: {}
        )
    }
}

#Preview("Catalog — Light") {
    ComponentCatalogView()
        .preferredColorScheme(.light)
}

#Preview("Catalog — Dark") {
    ComponentCatalogView()
        .preferredColorScheme(.dark)
}

#Preview("Catalog — Accessibility XL") {
    ComponentCatalogView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
