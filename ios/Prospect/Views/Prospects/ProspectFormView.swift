// Views/Prospects/ProspectFormView.swift
// Create / edit a prospect. Four fields, three quick choices, an optional note.
// The save button stays pinned above the keyboard.
import SwiftUI

struct ProspectFormView: View {
    @State private var viewModel: ProspectFormViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Field { case prenom, nom, email, phone, notes }
    @FocusState private var focused: Field?
    @State private var touched: Set<Field> = []

    let isReadOnly: Bool
    let onSave: (Prospect) -> Void

    init(mode: ProspectFormMode, programs: [Program], authorName: String = "", isReadOnly: Bool = false, onSave: @escaping (Prospect) -> Void) {
        _viewModel = State(initialValue: ProspectFormViewModel(mode: mode, programs: programs, authorName: authorName))
        self.isReadOnly = isReadOnly
        self.onSave = onSave
    }

    private var isCreate: Bool { if case .create = viewModel.mode { return true } else { return false } }

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                // Name: big, borderless, like an issue title.
                VStack(alignment: .leading, spacing: Space.xs) {
                    TextField("", text: $vm.prenom, prompt: Text("Prénom").foregroundStyle(Color.inkTertiary))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .prenom)
                        .submitLabel(.next)
                        .onSubmit { focused = .nom }
                    TextField("", text: $vm.nom, prompt: Text("Nom").foregroundStyle(Color.inkTertiary))
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .nom)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }
                }
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
                .tint(Color.accent)

                // Properties as pills; each opens a native menu.
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: Space.s) {
                    if !vm.programs.isEmpty {
                        let current = vm.programs.first { $0.id == vm.programId }
                        optionPill(label: current?.name ?? "Choisir un programme",
                                   leading: AnyView(Circle().fill(current?.swiftUIColor ?? Color.inkTertiary).frame(width: 9, height: 9)),
                                   dimmed: current == nil, needsAttention: current == nil) {
                            ForEach(vm.programs) { program in
                                Button { vm.programId = vm.programId == program.id ? nil : program.id } label: {
                                    if vm.programId == program.id { Label(program.name, systemImage: "checkmark") } else { Text(program.name) }
                                }
                            }
                        }
                    }
                    optionPill(label: vm.statut.shortLabel, leading: AnyView(StatusRing(statut: vm.statut, size: 15))) {
                        ForEach(Statut.allCases) { st in
                            Button { vm.statut = st } label: {
                                if vm.statut == st { Label(st.shortLabel, systemImage: "checkmark") } else { Text(st.shortLabel) }
                            }
                        }
                    }
                    optionPill(label: vm.niveauActuel.rawValue, leading: AnyView(Image(systemName: "graduationcap").font(.system(size: 12)))) {
                        ForEach(NiveauActuel.allCases) { level in
                            Button { vm.niveauActuel = level } label: {
                                if vm.niveauActuel == level { Label(level.rawValue, systemImage: "checkmark") } else { Text(level.rawValue) }
                            }
                        }
                    }
                  }
                  .padding(.horizontal, Space.l)
                }
                .padding(.horizontal, -Space.l)

                // Contact, as a grouped block of rows.
                VStack(spacing: 0) {
                    detailRow(icon: "envelope") {
                        TextField("", text: $vm.email, prompt: Text("Email").foregroundStyle(Color.inkTertiary))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focused = .phone }
                    }
                    Rule().padding(.leading, 48)
                    detailRow(icon: "phone") {
                        TextField("", text: $vm.telephone, prompt: Text("Téléphone").foregroundStyle(Color.inkTertiary))
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .focused($focused, equals: .phone)
                    }
                    Rule().padding(.leading, 48)
                    detailRow(icon: "text.alignleft") {
                        TextField("", text: $vm.notes, prompt: Text("Note").foregroundStyle(Color.inkTertiary), axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focused, equals: .notes)
                    }
                }
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                if isCreate {
                    Text("En enregistrant, vous confirmez que cette personne accepte d'être recontactée.")
                        .font(.textFootnote)
                        .foregroundStyle(Color.inkTertiary)
                }
                if showEmailError { InlineError(text: "Adresse email invalide") }
                if showPhoneError { InlineError(text: "Numéro invalide") }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xl)
            .disabled(isReadOnly)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PaperBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCard2, in: Circle())
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Fermer")
                Spacer()
                Text(isReadOnly ? "Prospect" : (isCreate ? "Nouveau prospect" : "Modifier"))
                    .font(.textSub.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Color.clear.frame(width: 55, height: 55)
            }
            .padding(.horizontal, Space.s)
            .padding(.top, Space.xs)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if !isReadOnly { saveBar } }
        .alert("Erreur", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: focused) { old, _ in if let old { touched.insert(old) } }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var showEmailError: Bool { touched.contains(.email) && !viewModel.email.isEmpty && !viewModel.emailIsValid }
    private var showPhoneError: Bool { touched.contains(.phone) && !viewModel.telephone.isEmpty && !viewModel.phoneIsValid }

    private func optionPill<Items: View>(label: String, leading: AnyView, dimmed: Bool = false,
                                          needsAttention: Bool = false,
                                          @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 7) {
                leading
                Text(label)
                    .font(.textSub.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .foregroundStyle(dimmed ? Color.inkTertiary : Color.inkPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.surfaceCard2, in: Capsule())
            .overlay { if needsAttention { Capsule().strokeBorder(Color.accent, lineWidth: 1.5) } }
            .contentShape(Capsule())
        }
    }

    private func detailRow<Field: View>(icon: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.inkTertiary)
                .frame(width: 20)
            field()
                .font(.textBody)
                .foregroundStyle(Color.inkPrimary)
                .tint(Color.accent)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 55)
    }

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            ZStack {
                Text(isCreate ? "Ajouter" : "Enregistrer").opacity(viewModel.isSaving ? 0 : 1)
                if viewModel.isSaving { ProgressView().tint(Color.onAccent) }
            }
        }
        .buttonStyle(.primary)
        .disabled(!viewModel.isValid || viewModel.isSaving)
        .accessibilityIdentifier("saveProspect")
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    private func save() async {
        focused = nil
        if let saved = await viewModel.save() {
            Haptics.success()
            onSave(saved)
            dismiss()
        } else {
            Haptics.error()
        }
    }
}

#Preview("Nouveau") {
    let state = AppState.preview()
    return ProspectFormView(mode: .create(session: TestPreviewData.session), programs: state.programs) { _ in }
        .environment(state)
}

#if DEBUG
enum TestPreviewData {
    static let session = Session(
        id: UUID(), name: "Salon", date: "2026-11-14", isArchived: false, statutSession: .enCours,
        preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0, programObjectives: [:], createdAt: "2026-10-01T09:00:00.000Z"
    )
}
#endif
