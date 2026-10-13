// Views/Components/LanguageMenu.swift
// The language picker: English or French, applied at once. A round globe button on the first screen,
// a row in the profile.
import SwiftUI

struct LanguageMenu: View {
    enum Style { case icon, row }

    @Environment(AppState.self) private var appState
    var style: Style = .icon

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    Haptics.selection()
                    appState.setLanguage(language)
                } label: {
                    if language == appState.language {
                        Label(language.nativeName, systemImage: "checkmark")
                    } else {
                        Text(language.nativeName)
                    }
                }
            }
        } label: {
            switch style {
            case .icon:
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceCard2, in: Circle())
                    .frame(width: 55, height: 55)
                    .contentShape(Rectangle())
            case .row:
                HStack(spacing: Space.m) {
                    Image(systemName: "globe").foregroundStyle(Color.inkSecondary).frame(width: 24)
                    Text(L("Language")).font(.textBody).foregroundStyle(Color.inkPrimary)
                    Spacer()
                    Text(appState.language.nativeName).font(.textBody).foregroundStyle(Color.inkSecondary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.inkTertiary)
                }
                .padding(.horizontal, Space.l)
                .frame(minHeight: 60)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(L("Language"))
        .accessibilityIdentifier("languageMenu")
    }
}
