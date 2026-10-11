// Views/Components/FilterToggleStyle.swift
// Pill-shaped toggle used in all filter sheets.
import SwiftUI

struct FilterToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: configuration.isOn ? 8 : 0) {
                configuration.label
                    .font(.geistSubheadline)
                    .lineLimit(1)

                if configuration.isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.geistSubheadline)
                }
            }
            .padding(10)
            .background(
                configuration.isOn ? Color.accent : Color.gray800,
                in: Capsule()
            )
            .foregroundStyle(configuration.isOn ? Color.gray900 : Color.gray100)
            .animation(nil, value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}
