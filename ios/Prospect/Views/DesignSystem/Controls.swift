// Views/DesignSystem/Controls.swift
// Buttons, fields, tabs and chips. Flat, ink-on-paper, hairline outlines. No glow, no gradient.
import SwiftUI

// MARK: - Buttons

/// Solid ink. The one primary action of a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.textHeadline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(Color.accent, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.26)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(configuration.isPressed ? nil : .curve(Motion.micro), value: configuration.isPressed)
            .animation(.curve(Motion.micro), value: isEnabled)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// Outlined. For the alternative action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .inkPrimary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.textSub.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(configuration.isPressed ? Color.rule : Color.surfaceCard2, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(configuration.isPressed ? nil : .curve(Motion.micro), value: configuration.isPressed)
    }
}

/// Underlined text action.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.textSub.weight(.semibold))
            .foregroundStyle(Color.inkPrimary)
            .underline(true, color: Color.ruleStrong)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}
extension ButtonStyle where Self == LinkButtonStyle {
    static var link: LinkButtonStyle { LinkButtonStyle() }
}

// MARK: - Field

/// A boxed field with a small tracked-capitals label. Focus is a heavier ink outline: no glow.
struct LabeledField<Content: View>: View {
    let title: String
    var isFocused: Bool = false
    var hasError: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.textCaption.weight(.medium))
                .foregroundStyle(hasError ? Color.error : Color.inkTertiary)
            content()
                .font(.textBody)
                .foregroundStyle(Color.inkPrimary)
                .tint(Color.accent)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(
                    hasError ? Color.error : (isFocused ? Color.accent.opacity(0.7) : Color.clear),
                    lineWidth: 1.5
                )
        }
        .animation(.curve(0.15), value: isFocused)
        .animation(.curve(0.15), value: hasError)
    }
}

// MARK: - Code entry

/// One square per character, driven by a single hidden text field so paste,
/// autofill and the system keyboard all work.
struct CodeEntryField: View {
    @Binding var code: String
    var length = 6
    var hasError = false
    /// Changes whenever the field should shake (bump it after a failed attempt).
    var shakeTrigger = 0
    var onComplete: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var caretVisible = true

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .focused($focused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .keyboardType(.asciiCapable)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityLabel(L("Session code"))
                .onChange(of: code) { _, new in
                    let cleaned = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(length))
                    if cleaned != new { code = cleaned }
                    if cleaned.count == length { focused = false; onComplete() }
                    else if !new.isEmpty { Haptics.selection() }
                }

            HStack(spacing: Space.s) {
                ForEach(0..<length, id: \.self) { index in
                    cell(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .modifier(ShakeEffect(travel: 8, shakes: 3, animatableData: CGFloat(shakeTrigger)))
        .onAppear {
            withAnimation(.curve(0.55).repeatForever(autoreverses: true)) { caretVisible.toggle() }
        }
    }

    private func cell(at index: Int) -> some View {
        let chars = Array(code)
        let isActive = focused && index == min(chars.count, length - 1) && chars.count < length
        let char = index < chars.count ? String(chars[index]) : ""
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(Color.surfaceCard)
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(
                    hasError ? Color.error : (isActive ? Color.ruleStrong : Color.rule),
                    lineWidth: isActive || hasError ? 2 : 1
                )
            Text(char)
                .font(.numeral(30))
                .foregroundStyle(Color.inkPrimary)
                .transition(.opacity)
                .id(char)
            if isActive && char.isEmpty {
                Rectangle().fill(Color.inkPrimary).frame(width: 2, height: 26).opacity(caretVisible ? 1 : 0.1)
            }
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .animation(.curve(0.12), value: char)
        .animation(.curve(0.12), value: isActive)
    }
}

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 10
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes), y: 0))
    }
}

// MARK: - Underline tabs

/// Text tabs over a hairline; a heavier rule slides under the selected one.
struct UnderlineTabs<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    @Namespace private var underline

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(.curve(0.25)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.textSub.weight(.medium))
                        .foregroundStyle(selected ? Color.inkPrimary : Color.inkTertiary)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background {
                            if selected {
                                Capsule().fill(Color.surfaceCard2)
                                    .matchedGeometryEffect(id: "tab", in: underline)
                            }
                        }
                        .frame(minHeight: 55)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Monogram

/// Initials in a hairline square. Used for people; there are no gradient avatars.
struct Monogram: View {
    let name: String
    var size: CGFloat = 40

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(Color.inkPrimary)
            .frame(width: size, height: size)
            .background(Color.surfaceCard2, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Choice chip

/// A selectable rectangle. Selected = solid ink. A tint adds a small colour marker.
struct ChoiceChip: View {
    let title: String
    var isSelected: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 7) {
                if let tint {
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.textSub.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.inkPrimary : Color.inkSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .background(isSelected ? Color.surfaceCard2 : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(isSelected ? Color.clear : Color.rule, lineWidth: 1) }
            .animation(.curve(0.12), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Inline error

struct InlineError: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.textFootnote.weight(.semibold))
            .foregroundStyle(Color.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }
}
