// Views/OrganizationSettingsView.swift
// Admin-only: organization name, what its events are called, and its program list.
import SwiftUI

struct OrganizationSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var eventLabel = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var programToEdit: Program?
    @State private var showNewProgram = false
    @State private var programToDelete: Program?

    private let service: ProspectServiceProtocol = ProspectService.shared

    private var hasChanges: Bool {
        guard let org = appState.currentOrganization else { return false }
        let n = name.trimmingCharacters(in: .whitespaces)
        let l = eventLabel.trimmingCharacters(in: .whitespaces)
        return !n.isEmpty && !l.isEmpty && (n != org.name || l != org.eventLabel)
    }

    var body: some View {
        Form {
            Section("Organisation") {
                TextField("Nom", text: $name)
                TextField("Nom des événements (ex. JPO, Salon)", text: $eventLabel)
            }
            .themedRowBackground()

            if hasChanges {
                Section {
                    Button {
                        Task { await saveOrganization() }
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Enregistrer").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSaving)
                }
                .themedRowBackground()
            }

            Section {
                ForEach(appState.programs) { program in
                    Button {
                        programToEdit = program
                    } label: {
                        HStack {
                            Circle().fill(program.swiftUIColor).frame(width: 12, height: 12)
                            Text(program.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.geistCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            programToDelete = program
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                .onMove { from, to in Task { await movePrograms(from: from, to: to) } }

                Button {
                    showNewProgram = true
                } label: {
                    Label("Ajouter un programme", systemImage: "plus")
                }
            } header: {
                Text("Programmes")
            } footer: {
                Text("Les formations, filières ou offres auxquelles s'intéressent vos prospects. Maintenez et glissez pour réordonner.")
            }
            .themedRowBackground()
        }
        .themedListBackground()
        .themedNavigationBar()
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = appState.currentOrganization?.name ?? ""
            eventLabel = appState.eventLabel
        }
        .task { await appState.reloadPrograms() }
        .sheet(item: $programToEdit) { program in
            ProgramEditor(program: program) { name, color in
                _ = try await service.updateProgram(id: program.id, name: name, color: color, sortOrder: nil)
                await appState.reloadPrograms()
            }
        }
        .sheet(isPresented: $showNewProgram) {
            ProgramEditor(program: nil) { name, color in
                _ = try await service.createProgram(name: name, color: color)
                await appState.reloadPrograms()
            }
        }
        .alert(
            "Supprimer « \(programToDelete?.name ?? "") » ?",
            isPresented: Binding(get: { programToDelete != nil }, set: { if !$0 { programToDelete = nil } })
        ) {
            Button("Supprimer", role: .destructive) {
                if let program = programToDelete { Task { await deleteProgram(program) } }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les prospects concernés seront conservés, sans programme.")
        }
        .alert("Erreur", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func saveOrganization() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await service.updateOrganization(
                name: name.trimmingCharacters(in: .whitespaces),
                eventLabel: eventLabel.trimmingCharacters(in: .whitespaces)
            )
            appState.apply(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProgram(_ program: Program) async {
        do {
            try await service.deleteProgram(id: program.id)
            await appState.reloadPrograms()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func movePrograms(from: IndexSet, to: Int) async {
        var reordered = appState.programs
        reordered.move(fromOffsets: from, toOffset: to)
        appState.programs = reordered
        do {
            for (index, program) in reordered.enumerated() where program.sortOrder != index {
                _ = try await service.updateProgram(id: program.id, name: nil, color: nil, sortOrder: index)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await appState.reloadPrograms()
    }
}

/// Create or edit one program: name + colour.
private struct ProgramEditor: View {
    let program: Program?
    let onSave: (_ name: String, _ color: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var isSaving = false
    @State private var errorText: String?

    init(program: Program?, onSave: @escaping (_ name: String, _ color: String) async throws -> Void) {
        self.program = program
        self.onSave = onSave
        _name = State(initialValue: program?.name ?? "")
        _color = State(initialValue: program?.color ?? Program.palette.randomElement() ?? "#3366E6")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("ex. Informatique", text: $name)
                }
                .themedRowBackground()
                Section("Couleur") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Program.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if hex.caseInsensitiveCompare(color) == .orderedSame {
                                        Image(systemName: "checkmark").font(.geistHeadline).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { color = hex }
                                .accessibilityLabel(hex)
                                .accessibilityAddTraits(hex == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }
                .themedRowBackground()
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Color.error) }
                        .themedRowBackground()
                }
            }
            .themedListBackground()
            .themedNavigationBar()
            .navigationTitle(program == nil ? "Nouveau programme" : "Modifier le programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") { Task { await save() } }
                            .fontWeight(.bold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(name.trimmingCharacters(in: .whitespaces), color)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        OrganizationSettingsView()
    }
    .environment(AppState.preview())
}
