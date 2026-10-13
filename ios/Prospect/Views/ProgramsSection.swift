// Views/ProgramsSection.swift
// The list of programs, as a section of the event editor ("Modifier"). Programs are shared in every invitation.
import SwiftUI

struct ProgramsSection: View {
    @Environment(AppState.self) private var appState

    @State private var errorMessage: String?
    @State private var programToEdit: Program?
    @State private var showNewProgram = false
    @State private var reordering = false

    private let service: ProspectServiceProtocol = ProspectService.current

    var body: some View {
        NumberedSection(number: "", title: L("Programs")) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(appState.programs.enumerated()), id: \.element.id) { index, program in
                    HStack(spacing: Space.m) {
                        Button { if !reordering { programToEdit = program } } label: {
                            HStack(spacing: Space.m) {
                                Circle().fill(program.swiftUIColor).frame(width: 12, height: 12)
                                Text(program.name).font(.textBody).foregroundStyle(Color.inkPrimary)
                                Spacer()
                                if !reordering {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.inkTertiary)
                                }
                            }
                            .frame(minHeight: 55)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if reordering {
                            moveButton("chevron.up", enabled: index > 0) { Task { await move(index, by: -1) } }
                            moveButton("chevron.down", enabled: index < appState.programs.count - 1) { Task { await move(index, by: 1) } }
                        }
                    }
                    Rule()
                }

                HStack(spacing: Space.l) {
                    Button { showNewProgram = true } label: {
                        Label(L("Add"), systemImage: "plus")
                            .font(.textSub.weight(.semibold))
                            .frame(minHeight: 55)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                    if appState.programs.count > 1 {
                        Button {
                            Haptics.selection()
                            withAnimation(.curve(Motion.micro)) { reordering.toggle() }
                        } label: {
                            Image(systemName: reordering ? "checkmark" : "arrow.up.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 55, height: 55)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(reordering ? L("End") : L("Reorder"))
                    }
                }
                .foregroundStyle(Color.inkPrimary)
            }
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
        .alert(L("Error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
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
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                Text(program == nil ? L("New\nprogram.") : L("Edit\nprogram."))
                    .font(.displayXL)
                    .foregroundStyle(Color.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 44)

                LabeledField(title: L("Last name"), isFocused: nameFocused) {
                    TextField(L("e.g. Computer Science"), text: $name).focused($nameFocused)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    Text(L("Color"))
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
                    Button(L("Delete this program")) { confirmDelete = true }
                        .buttonStyle(.secondary(tint: .error))
                        .padding(.top, Space.s)
                        .confirmationDialog(L("Delete this program?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button(L("Delete"), role: .destructive) { Task { await perform(onDelete) } }
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
                    Text(L("Save")).opacity(isSaving ? 0 : 1)
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
            .accessibilityLabel(L("Close"))
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
