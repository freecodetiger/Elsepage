import SwiftUI

/// User-facing preferences for the inline authorship shown in conversations.
/// Names and symbol-based avatars are shared with `ReflectionConversationView`
/// through the same `AppStorage` keys, so changes take effect immediately.
struct ConversationIdentitySettingsView: View {
    @AppStorage("profile.userDisplayName") private var userDisplayName = "我"
    @AppStorage("profile.assistantDisplayName") private var assistantDisplayName = "页外"
    @AppStorage("profile.userAvatarSymbol") private var userAvatarSymbol = "person.crop.circle.fill"
    @AppStorage("profile.assistantAvatarSymbol") private var assistantAvatarSymbol = "cpu"

    private let userSymbols = [
        "person.crop.circle.fill",
        "person.fill",
        "figure.wave",
        "book.closed.fill",
        "sparkles",
        "sun.max.fill"
    ]

    private let assistantSymbols = [
        "cpu",
        "sparkles",
        "brain.head.profile",
        "quote.bubble.fill",
        "wand.and.stars",
        "circle.hexagongrid.fill"
    ]

    var body: some View {
        Form {
            Section {
                TextField("用户名", text: $userDisplayName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                AvatarSymbolPicker(
                    title: "头像",
                    selection: $userAvatarSymbol,
                    symbols: userSymbols
                )
            } header: {
                Text("我")
            } footer: {
                Text("显示在阅读记录和追问的署名位置。")
            }

            Section {
                TextField("AI 名称", text: $assistantDisplayName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                AvatarSymbolPicker(
                    title: "头像",
                    selection: $assistantAvatarSymbol,
                    symbols: assistantSymbols
                )
            } header: {
                Text("AI")
            } footer: {
                Text("显示在 AI 回应和依据摘要上方。")
            }

            Section("预览") {
                VStack(alignment: .leading, spacing: 16) {
                    inlinePreview(
                        name: normalized(userDisplayName, fallback: "我"),
                        symbol: userAvatarSymbol,
                        text: "这是一次阅读之后留下的想法。"
                    )
                    Divider()
                    inlinePreview(
                        name: normalized(assistantDisplayName, fallback: "页外"),
                        symbol: assistantAvatarSymbol,
                        text: "这是页外对这条记录的回应。"
                    )
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("恢复默认") {
                    userDisplayName = "我"
                    assistantDisplayName = "页外"
                    userAvatarSymbol = "person.crop.circle.fill"
                    assistantAvatarSymbol = "cpu"
                }
            }
        }
        .navigationTitle("对话身份")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inlinePreview(name: String, symbol: String, text: String) -> some View {
        (
            Text(Image(systemName: symbol))
            + Text("  \(name)：")
                .fontWeight(.semibold)
            + Text(" \(text)")
        )
        .font(.body)
        .foregroundStyle(Color.primary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct AvatarSymbolPicker: View {
    let title: String
    @Binding var selection: String
    let symbols: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            selection = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(.secondary.opacity(0.10), in: Circle())
                                .overlay {
                                    Circle().stroke(
                                        selection == symbol ? Color.primary : Color.secondary.opacity(0.16),
                                        lineWidth: selection == symbol ? 2 : 1
                                    )
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(avatarAccessibilityLabel(symbol))
                        .accessibilityAddTraits(selection == symbol ? .isSelected : AccessibilityTraits())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func avatarAccessibilityLabel(_ symbol: String) -> String {
        switch symbol {
        case "person.crop.circle.fill": "默认用户头像"
        case "person.fill": "人物头像"
        case "figure.wave": "挥手人物头像"
        case "book.closed.fill": "书本头像"
        case "sparkles": "闪光头像"
        case "sun.max.fill": "太阳头像"
        case "cpu": "机器人默认头像"
        case "brain.head.profile": "思考头像"
        case "quote.bubble.fill": "回应气泡头像"
        case "wand.and.stars": "整理头像"
        case "circle.hexagongrid.fill": "网格头像"
        default: symbol
        }
    }
}
