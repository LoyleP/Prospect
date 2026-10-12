// Views/OrganizationSettingsView.swift
// Organizer only: what events are called, and the list of programs shared in every invitation.
import SwiftUI

struct OrganizationSettingsView: View {
    @Environment(AppState.self) private var appState

    private enum Field { case label }

    @State private var eventLabel = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var programToEdit: Program?
    @State private var showNewProgram = false
    @State private var reordering = false
    @State private var toast: Toast?
    @FocusState private var focused: Field?

    private let service: ProspectServiceProtocol = ProspectService.current

    private var hasChanges: Bool {
        guard let org = appState.currentOrganization else { return false }
        let l = eventLabel.trimmingCharacters(in: .whitespaces)
        return !l.isEmpty && l != org.eventLabel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ScreenHeading(label: appState.agentNom, title: "Réglages")

                NumberedSection(number: "01", title: "Événements") {
                    VStack(spacing: Space.m) {
                        LabeledField(title: "Vos événements s'appellent", isFocused: focused == .label) {
                            TextField("Événement, JPO, Salon…", text: $eventLabel).focused($focused, equals: .label)
                        }
                        if hasChanges {
                            Button {
                                Task { await saveOrganization() }
                            } label: {
                                ZStack {
                                    Text("Enregistrer").opacity(isSaving ? 0 : 1)
                                    if isSaving { ProgressView().tint(Color.onAccent) }
                                }
                            }
                            .buttonStyle(.primary)
                            .disabled(isSaving)
                            .transition(.opacity)
                        }
                    }
                    .animation(.curve(0.2), value: hasChanges)
                }

                NumberedSection(number: "02", title: "Programmes") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(appState.programs.enumerated()), id: \.element.id) { index, program in
                            HStack(spacing: Space.m) {
                                Button { if !reordering { programToEdit = program } } label: {
                                    HStack(spacing: Space.m) {
                                        RoundedRectangle(cornerRadius: 3).fill(program.swiftUIColor).frame(width: 14, height: 14)
                                        Text(program.name).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                                        Spacer()
                                        if !reordering {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color.inkTertiary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if reordering {
                                    moveButton("chevron.up", enabled: index > 0) { Task { await move(index, by: -1) } }
                                    moveButton("chevron.down", enabled: index < appState.programs.count - 1) { Task { await move(index, by: 1) } }
                                }
                            }
                            .padding(.vertical, Space.m)
                            Rule()
                        }

                        HStack(spacing: Space.l) {
                            Button { showNewProgram = true } label: {
                                Label("Ajouter un programme", systemImage: "plus").font(.textSub.weight(.semibold))
                            }
                            Spacer()
                            if appState.programs.count > 1 {
                                Button(reordering ? "Terminer" : "Réordonner") { reordering.toggle() }
                                    .buttonStyle(.link)
                            }
                        }
                        .foregroundStyle(Color.inkPrimary)
                        .padding(.top, Space.l)

                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PaperBackground())
        .toast($toast)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            eventLabel = appState.eventLabel
        }
        .task { await appState.reloadPrograms() }
        .sheet(item: $programToEdit) { program in
            ProgramEditor(
                program: program,
                onSave: { name, color in
                    _ = try await service.updateProgram(id: program.id, name: name, color: color, sortOrder: nil)
                    await appState.reloadPrograms()
                },
                onDelete: {
                    try await service.deleteProgram(id: program.id)
                    await appState.reloadPrograms()
                }
            )
        }
        .sheet(isPresented: $showNewProgram) {
            ProgramEditor(
                program: nil,
                onSave: { name, color in
                    _ = try await service.createProgram(name: name, color: color)
                    await appState.reloadPrograms()
                },
                onDelete: nil
            )
        }
        .alert("Erreur", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func moveButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color.inkPrimary : Color.inkTertiary.opacity(0.4))
                .frame(width: 55, height: 55)
                .contentShape(Rectangle())
                .overlay { RoundedRectangle(cornerRadius: Radius.s + 2, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func saveOrganization() async {
        focused = nil
        isSaving = true
        defer { isSaving = false }
        do {
            appState.updateIdentity(eventLabel: eventLabel.trimmingCharacters(in: .whitespaces))
            toast = Toast(message: "Réglages enregistrés", style: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ index: Int, by delta: Int) async {
        var reordered = appState.programs
        let target = index + delta
        guard reordered.indices.contains(target) else { return }
        reordered.swapAt(index, target)
        appState.programs = reordered
        do {
            for (i, program) in reordered.enumerated() where program.sortOrder != i {
                _ = try await service.updateProgram(id: program.id, name: nil, color: nil, sortOrder: i)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await appState.reloadPrograms()
    }
}

/// Create or edit one program: name and colour.
private struct ProgramEditor: View {
    let program: Program?
    let onSave: (_ name: String, _ color: String) async throws -> Void
    let onDelete: (() async throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(program: Program?, onSave: @escaping (_ name: String, _ color: String) async throws -> Void, onDelete: (() async throws -> Void)?) {
        self.program = program
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: program?.name ?? "")
        _color = State(initialValue: program?.color ?? Program.palette.randomElement() ?? "#3366E6")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text(program == nil ? "Nouveau\nprogramme." : "Modifier\nle programme.")
                    .font(.displayXL)
                    .foregroundStyle(Color.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 44)

                LabeledField(title: "Nom", isFocused: nameFocused) {
                    TextField("ex. Informatique", text: $name).focused($nameFocused)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Couleur")
                        .font(.textCaption.weight(.medium))
                        .foregroundStyle(Color.inkTertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 5), spacing: Space.s) {
                        ForEach(Program.palette, id: \.self) { hex in
                            let selected = hex.caseInsensitiveCompare(color) == .orderedSame
                            Button {
                                Haptics.selection()
                                color = hex
                            } label: {
                                RoundedRectangle(cornerRadius: Radius.s + 2, style: .continuous)
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(height: 55)
                                    .overlay {
                                        if selected {
                                            Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Radius.s + 2, style: .continuous)
                                            .strokeBorder(selected ? Color.ruleStrong : Color.clear, lineWidth: 2).padding(-3)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hex)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }

                if let errorText { InlineError(text: errorText) }

                if let onDelete, program != nil {
                    Button("Supprimer ce programme") { confirmDelete = true }
                        .buttonStyle(.secondary(tint: .error))
                        .padding(.top, Space.s)
                        .confirmationDialog("Supprimer ce programme ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Supprimer", role: .destructive) { Task { await perform(onDelete) } }
                        }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PaperBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                Task { await perform { try await onSave(name.trimmingCharacters(in: .whitespaces), color) } }
            } label: {
                ZStack {
                    Text("Enregistrer").opacity(isSaving ? 0 : 1)
                    if isSaving { ProgressView().tint(Color.onInk) }
                }
            }
            .buttonStyle(.primary)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surfaceBackground)
        .onAppear { if program == nil { nameFocused = true } }
    }

    private func perform(_ action: () async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        do {
            try await action()
            Haptics.success()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }
}

#Preview {
    NavigationStack { OrganizationSettingsView() }
        .environment(AppState.preview())
}
