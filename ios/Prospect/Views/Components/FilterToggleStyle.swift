// Views/Components/FilterToggleStyle.swift
// Toggle styled as a ChoiceChip, for the older filter screens.
import SwiftUI

struct FilterToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(.textSub.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(configuration.isOn ? Color.onInk : Color.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(configuration.isOn ? Color.inkPrimary : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s + 2, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.s + 2, style: .continuous)
                        .strokeBorder(configuration.isOn ? Color.inkPrimary : Color.rule, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
