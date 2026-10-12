// Views/Prospects/EventEditorSheet.swift
// Create or edit an event: name, date, and (when editing) its status.
import SwiftUI

struct EventEditorSheet: View {
    enum Mode { case create, edit }

    let mode: Mode
    let eventLabel: String
    @Binding var name: String
    @Binding var date: Date
    @Binding var status: SessionStatut
    @Binding var endsAt: Date?
    let canSave: Bool
    let isSaving: Bool
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Text(mode == .create ? "Créer : \(eventLabel)" : "Modifier")
                        .font(.displayM.weight(.bold))
                        .foregroundStyle(Color.inkPrimary)
                        .padding(.trailing, 40)

                    LabeledField(title: "Nom", isFocused: nameFocused) {
                        TextField("ex. \(eventLabel) de novembre", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityIdentifier("eventNameField")
                    }

                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("Date")
                            .font(.textCaption.weight(.semibold))
                            .foregroundStyle(Color.inkSecondary)
                            .tracking(0.6)
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "fr_FR"))
                            .tint(Color.inkPrimary)
                            .card(padding: Space.s)
                    }

                    VStack(alignment: .leading, spacing: Space.m) {
                        Toggle(isOn: Binding(
                            get: { endsAt != nil },
                            set: { endsAt = $0 ? Self.merge(time: Self.defaultEnd(on: date), into: date) : nil }
                        )) {
                            Label("Rappel de fin", systemImage: "bell").font(.textBody).foregroundStyle(Color.inkPrimary)
                        }
                        .tint(Color.accent)
                        if let end = endsAt {
                            DatePicker("Heure de fin", selection: Binding(
                                get: { end },
                                set: { endsAt = Self.merge(time: $0, into: date) }
                            ), displayedComponents: .hourAndMinute)
                            .environment(\.locale, Locale(identifier: "fr_FR"))
                            .tint(Color.accent)
                        }
                    }
                    .padding(Space.l)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

                    if mode == .edit {
                        ProgramsSection()
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text("Statut")
                                .font(.textCaption.weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                                .tracking(0.6)
                            UnderlineTabs(options: SessionStatut.allCases, selection: $status) { $0.label }
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onSave) {
                ZStack {
                    Text(mode == .create ? "Créer" : "Enregistrer").opacity(isSaving ? 0 : 1)
                    if isSaving { ProgressView().tint(Color.onAccent) }
                }
            }
            .buttonStyle(.primary)
            .disabled(!canSave || isSaving)
            .accessibilityIdentifier("saveEvent")
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceCard2, in: Circle())
                    .frame(width: 55, height: 55)
                    .contentShape(Rectangle())
            }
            .padding(Space.l)
            .accessibilityLabel("Fermer")
        }
        .presentationDragIndicator(.visible)
        .onAppear { if mode == .create { nameFocused = true } }
    }

    /// The date's day with another date's hour and minute.
    private static func merge(time: Date, into day: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 17, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private static func defaultEnd(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
    }
}
