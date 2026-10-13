// Views/DesignSystem/Components.swift
// Smaller pieces reused across screens: stamps, live dot, icon buttons, empty and loading
// states, and the bottom tab bar.
import SwiftUI

// MARK: - Stamps

extension Statut {
    /// Full label for exports. The stored value of the first two stages is still "Curieux" / "Intéressé".
    var exportLabel: String {
        switch self {
        case .curieux:      return L("Discovery")
        case .interesse:    return L("Project defined")
        case .rdvInfo:      return L("Info meeting booked")
        case .rdvAdmission: return L("Admission meeting booked")
        }
    }

    /// Compact label for stamps.
    var shortLabel: String {
        switch self {
        case .curieux:      return L("Discovery")
        case .interesse:    return L("Project defined")
        case .rdvInfo:      return L("Info meeting")
        case .rdvAdmission: return L("Admission meeting")
        }
    }
}

/// A small tinted capsule: "En direct", roles.
struct Stamp: View {
    let text: String
    let color: Color
    var showsLiveDot = false

    var body: some View {
        HStack(spacing: 5) {
            if showsLiveDot { LiveDot() }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .fixedSize()
    }
}

/// A quiet status: a small colour square and one word. No box.
struct StatusLabel: View {
    let text: String
    let color: Color
    var showsDot = true

    var body: some View {
        HStack(spacing: 6) {
            if showsDot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text)
                .font(.textCaption.weight(.semibold))
                .foregroundStyle(color)
        }
        .fixedSize()
    }
}

/// A prospect's pipeline stage.
struct StatusStamp: View {
    let statut: Statut

    var body: some View {
        StatusLabel(text: statut.shortLabel, color: statut.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Status: \(statut.shortLabel)"))
    }
}

extension SessionStatut {
    var tint: Color {
        switch self {
        case .enCours:     return .accent
        case .pasCommence: return .inkSecondary
        case .termine:     return .inkTertiary
        }
    }
}

/// An event's state. Only "En direct" gets the boxed stamp with the signal dot; the rest is plain text.
struct EventStatusStamp: View {
    let status: SessionStatut

    var body: some View {
        if status == .enCours {
            Stamp(text: L("Live"), color: status.tint, showsLiveDot: true)
        } else {
            StatusLabel(text: status.label, color: status.tint, showsDot: false)
        }
    }
}

/// A small pulsing signal-coloured dot. The only thing in the app that animates on its own.
struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Color.accent.opacity(0.35)).frame(width: 11, height: 11)
                .scaleEffect(pulse ? 1.0 : 0.45).opacity(pulse ? 0 : 0.9)
            Circle().fill(Color.accent).frame(width: 6, height: 6)
        }
        .frame(width: 11, height: 11)
        .onAppear { withAnimation(.curve(1.6).repeatForever(autoreverses: false)) { pulse = true } }
        .accessibilityHidden(true)
    }
}

// MARK: - Icon button

/// A square hairline button for headers: filter, calendar, close…
/// The round gray look shared by header buttons and header menus.
struct IconCircle: View {
    let systemImage: String
    var showsBadge = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.inkPrimary)
            .frame(width: 44, height: 44)
            .background(Color.surfaceCard2, in: Circle())
            .overlay(alignment: .topTrailing) {
                if showsBadge {
                    Circle().fill(Color.accent).frame(width: 10, height: 10)
                        .overlay { Circle().strokeBorder(Color.surfaceBackground, lineWidth: 2) }
                }
            }
            .frame(width: 55, height: 55)
            .contentShape(Rectangle())
    }
}

struct IconButton: View {
    let systemImage: String
    var label: String
    var showsBadge = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            IconCircle(systemImage: systemImage, showsBadge: showsBadge)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(label)
    }
}

/// Subtle press feedback for custom tappable surfaces.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            // Touch-down answers instantly; only letting go animates back.
            .animation(configuration.isPressed ? nil : .curve(Motion.micro), value: configuration.isPressed)
    }
}

// MARK: - Empty state

/// A sentence, not an illustration: what's missing, and the one thing to do about it.
struct EmptyStateView: View {
    let title: String
    /// Kept so existing call sites compile; never shown (the title and the action say it all).
    var message: String = ""
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title.hasSuffix(".") ? String(title.dropLast()) : title)
                .font(.textHeadline)
                .foregroundStyle(Color.inkPrimary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, Space.l)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.xxl)
    }
}

// MARK: - Placeholder rows

/// A placeholder shaped like a register line, shown while loading.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: 3).fill(Color.rule).frame(width: 26, height: 12)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Color.rule).frame(width: 150, height: 14)
                RoundedRectangle(cornerRadius: 3).fill(Color.rule.opacity(0.7)).frame(width: 96, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(Color.rule).frame(width: 64, height: 20)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Status ring

/// A pipeline stage drawn as a progress ring: dashed (curious), empty (interested),
/// half full (info meeting), full with a check (admission meeting).
struct StatusRing: View {
    let statut: Statut
    var size: CGFloat = 17

    var body: some View {
        let c = statut.color
        ZStack {
            switch statut {
            case .curieux:
                Circle().strokeBorder(c, style: StrokeStyle(lineWidth: 1.7, dash: [2.2, 2.2]))
            case .interesse:
                Circle().strokeBorder(c, lineWidth: 1.7)
            case .rdvInfo:
                Circle().strokeBorder(c, lineWidth: 1.7)
                Circle().trim(from: 0, to: 0.5).rotation(.degrees(90))
                    .fill(c).padding(3.2)
            case .rdvAdmission:
                Circle().fill(c)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(Color.surfaceBackground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A list group header: ring, name, count, and a quiet add control. No box, no rule.
struct StatusGroupHeader: View {
    let statut: Statut
    let count: Int
    var onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.s + 2) {
            StatusRing(statut: statut, size: 15)
            Text(statut.shortLabel)
                .font(.textSub.weight(.medium))
                .foregroundStyle(Color.inkSecondary)
            Text("\(count)")
                .font(.figure(13))
                .foregroundStyle(Color.inkTertiary)
                .contentTransition(.numericText())
                .animation(.curve(Motion.standard), value: count)
            Spacer()
            if let onAdd {
                Button { Haptics.tap(); onAdd() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.inkTertiary)
                        .frame(width: 55, height: 36, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Add: \(statut.shortLabel)"))
            }
        }
        .padding(.top, Space.s)
        .textCase(nil)
    }
}

// MARK: - Bottom tab bar

/// A floating capsule of icons, like Linear's: no labels, the selected tab sits in a lighter pill.
struct BottomTabBar: View {
    struct Item: Identifiable {
        let tab: AppState.MainTab
        let title: String
        let icon: String
        var id: AppState.MainTab { tab }
    }

    @Binding var selection: AppState.MainTab
    let items: [Item]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.tab == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(.curve(Motion.tab)) { selection = item.tab }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(selected ? Color.inkPrimary : Color.inkTertiary)
                        .frame(maxWidth: .infinity).frame(height: 55)
                        .background {
                            if selected { Capsule().fill(Color.surfaceCard2).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab-\(item.tab)")
            }
        }
        .padding(5)
        .background(Color.surfaceCard, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.rule, lineWidth: 1) }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Screen structure

extension View {
    /// A ruled register line on a transparent list.
    func registerRow() -> some View {
        self
            .padding(.vertical, 0)
            .listRowInsets(EdgeInsets(top: 0, leading: Space.l, bottom: 0, trailing: Space.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// The top of a tab screen: a small tracked-caps label above a heavy title.
struct ScreenHeading: View {
    let label: String
    let title: String

    var body: some View {
        Text(title.hasSuffix(".") ? String(title.dropLast()) : title)
            .font(.displayXL)
            .foregroundStyle(Color.inkPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(label), \(title)")
    }
}

/// A section: a hairline and a small caps title. (The `number` is kept for call-site compatibility
/// but no longer shown: numbering added noise.)
struct NumberedSection<Content: View>: View {
    let number: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.textSub.weight(.medium))
                    .foregroundStyle(Color.inkTertiary)
            }
            content()
        }
    }
}

/// A − / value / + control for whole numbers: big enough for a thumb, no slider.
struct QuantityControl: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...10_000
    var step = 1
    var suffix = ""

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { value = max(range.lowerBound, value - step) }
            Text("\(value)\(suffix)")
                .font(.figure(20, weight: .bold))
                .foregroundStyle(Color.inkPrimary)
                .frame(minWidth: 72)
                .contentTransition(.numericText())
                .animation(.curve(0.2), value: value)
            stepButton("plus") { value = min(range.upperBound, value + step) }
        }
        .overlay { RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.inkPrimary)
                .frame(width: 55, height: 55)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? L("Increase") : L("Decrease"))
    }
}

/// Copies text and reports it. Used for codes.
@MainActor
func copyToPasteboard(_ text: String) {
    UIPasteboard.general.string = text
    Haptics.success()
}
