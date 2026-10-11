// Views/ProspectFormView.swift
// Create/edit form for a prospect.
import SwiftUI

// MARK: - Individual field views

private struct PlainTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocorrection: Bool = true
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .autocorrectionDisabled(!autocorrection)
            .textInputAutocapitalization(autocapitalization)
            .focused($isFocused)
    }
}

private struct EmailField: View {
    @Binding var text: String
    @Binding var error: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("email@exemple.com", text: $text)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
            if let err = error {
                Text(err).font(.geistCaption).foregroundStyle(Color.error)
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { error = nil; return }
            let parts = trimmed.components(separatedBy: "@")
            error = (parts.count == 2 && parts[1].contains(".")) ? nil : "Format invalide"
        }
    }
}

private struct PhoneField: View {
    @Binding var text: String
    @Binding var error: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("+33 6 00 00 00 00", text: $text)
                .keyboardType(.phonePad)
                .focused($isFocused)
            if let err = error {
                Text(err)
                    .font(.geistCaption)
                    .foregroundStyle(Color.error)
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { error = nil; return }
            let digits = trimmed.filter { $0.isNumber }
            error = digits.count >= 6 ? nil : "Numéro invalide"
        }
    }
}

private struct NotesField: View {
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: 80)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Remarques, contexte…")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
            }
    }
}

// MARK: - Form Fields

private struct ProspectFormFields: View {
    @Bindable var vm: ProspectFormViewModel

    @State private var emailError: String? = nil
    @State private var phoneError: String? = nil

    var body: some View {
        Form {
            // MARK: Identité
            Section("Identité") {
                PlainTextField(placeholder: "Prénom", text: $vm.prenom)
                PlainTextField(placeholder: "Nom", text: $vm.nom)
            }
            .themedRowBackground()

            // MARK: Contact
            Section("Contact") {
                EmailField(text: $vm.email, error: $emailError)
                PhoneField(text: $vm.telephone, error: $phoneError)
            }
            .themedRowBackground()

            // MARK: Intérêt + Statut
            Section("Intérêt") {
                Picker("Statut", selection: $vm.statut) {
                    ForEach(Statut.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Programme", selection: $vm.programId) {
                    Text("Sans programme").tag(UUID?.none)
                    ForEach(vm.programs) { p in
                        Text(p.name).tag(UUID?.some(p.id))
                    }
                }
                .pickerStyle(.wheel)
                Picker("Niveau actuel", selection: $vm.niveauActuel) {
                    ForEach(NiveauActuel.allCases) { n in
                        Text(n.rawValue).tag(n)
                    }
                }
                .pickerStyle(.wheel)
            }
            .themedRowBackground()

            // MARK: Notes
            Section {
                NotesField(text: $vm.notes)
            }
            .themedRowBackground()
        }
        .themedListBackground()
        .themedNavigationBar()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        )
    }
}

// MARK: - ProspectFormView

struct ProspectFormView: View {
    @State private var viewModel: ProspectFormViewModel
    @Environment(\.dismiss) private var dismiss
    let onSave: (Prospect) -> Void

    /// Advisors and closed events open prospects without the save button.
    let isReadOnly: Bool

    init(mode: ProspectFormMode, programs: [Program], isReadOnly: Bool = false, onSave: @escaping (Prospect) -> Void) {
        _viewModel = State(initialValue: ProspectFormViewModel(mode: mode, programs: programs))
        self.isReadOnly = isReadOnly
        self.onSave = onSave
    }

    var body: some View {
        @Bindable var vm = viewModel
        ProspectFormFields(vm: viewModel)
            .disabled(isReadOnly)
            .navigationTitle(isReadOnly ? "Prospect" : vm.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .create = vm.mode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                        }
                    }
                }
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        saveButton(vm: vm)
                    }
                }
            }
            .alert("Erreur", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private func saveButton(vm: ProspectFormViewModel) -> some View {
        if vm.isSaving {
            ProgressView()
        } else {
            Button {
                Task {
                    if let saved = await vm.save() {
                        onSave(saved)
                        dismiss()
                    }
                }
            } label: {
                Text("Enregistrer")
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(!vm.isValid)
        }
    }
}
