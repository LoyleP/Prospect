// Views/SessionListView.swift
// The Prospects tab: owns the event list and shows the selected event's prospects.
// Event switching, creation and editing happen in sheets.
import SwiftUI

struct SessionListView: View {
    @State private var viewModel = SessionListViewModel()
    @State private var showProfile = false
    @State private var showEvents = false
    @State private var sessionForObjectives: SessionSummary?
    @State private var sessionForInvite: SessionSummary?
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var vm = viewModel
        Group {
            if vm.isLoading && vm.summaries.isEmpty {
                ProgressView().tint(Color.inkTertiary)
            } else if vm.summaries.isEmpty {
                EmptyStateView(
                    title: L("No sessions."),
                    message: appState.isAdmin
                        ? L("Create the first one, then invite your team.")
                        : L("Scan the organizer's invitation from your profile."),
                    actionTitle: appState.isAdmin ? L("Create a session") : nil,
                    action: appState.isAdmin ? { vm.showNewSessionSheet = true } : nil
                )
            } else if let selected = vm.selectedSummary {
                ProspectListView(
                    summary: selected,
                    isReadOnly: selected.statutSession == .termine || selected.isArchived || appState.isConseiller,
                    onShowProfile: { showProfile = true },
                    onShowEvents: { showEvents = true },
                    eventActions: appState.isAdmin ? EventActions(
                        edit: { vm.beginEdit(selected) },
                        objectives: { sessionForObjectives = selected },
                        toggleArchive: { Task { await vm.toggleArchive(selected) } },
                        delete: { vm.sessionToDelete = selected }
                    ) : nil
                )
                .id("\(selected.id)-\(selected.statutSession.rawValue)-\(selected.isArchived)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $sessionForObjectives) { session in
            ObjectivesView(session: session)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showEvents) {
            EventPickerSheet(
                summaries: vm.summaries,
                selectedId: vm.selectedSummary?.id,
                isAdmin: appState.isAdmin,
                eventLabel: appState.eventLabel,
                onSelect: { vm.selectedSummary = $0 },
                onCreate: { after { vm.showNewSessionSheet = true } },
                onEdit: { s in after { vm.beginEdit(s) } },
                onAccess: { s in after { sessionForInvite = s } },
                onObjectives: { s in after { sessionForObjectives = s } },
                onToggleArchive: { s in Task { await vm.toggleArchive(s) } },
                onDelete: { s in after { vm.sessionToDelete = s } }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.surfaceBackground)
        }
        .sheet(isPresented: $vm.showNewSessionSheet, onDismiss: { vm.newSessionPage = 0 }) {
            NewSessionSheet(page: $vm.newSessionPage) { draft in try await vm.createSession(draft) }
                .presentationDetents([.large])
                .presentationBackground(Color.surfaceBackground)
        }
        .sheet(item: $vm.sessionToEdit) { _ in
            EventEditorSheet(
                mode: .edit, eventLabel: appState.eventLabel,
                name: $vm.editSessionName, date: $vm.editSessionDate, status: $vm.editSessionStatut, endsAt: $vm.editSessionEndsAt,
                canSave: vm.canUpdate, isSaving: vm.isLoading
            ) { Task { await vm.commitEdit() } }
            .presentationDetents([.large])
            .presentationBackground(Color.surfaceBackground)
        }
        .sheet(item: $sessionForInvite) { summary in
            InvitationSheet(eventId: summary.id, eventName: summary.name)
                .presentationDetents([.large])
                .presentationBackground(Color.surfaceBackground)
        }
        .alert(
            L("Delete “\(vm.sessionToDelete?.name ?? "")”?"),
            isPresented: Binding(get: { vm.sessionToDelete != nil }, set: { if !$0 { vm.sessionToDelete = nil } })
        ) {
            Button(L("Delete"), role: .destructive) { Task { await vm.confirmDelete() } }
            Button(L("Cancel"), role: .cancel) { vm.sessionToDelete = nil }
        }
        .alert(L("Error"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { await vm.load() }
        .onChange(of: appState.route, initial: true) { _, route in handle(route) }
    }

    /// Presents a sheet after the picker's dismissal animation, so the two don't collide.
    private func after(_ work: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            work()
        }
    }

    private func handle(_ route: AppState.Route?) {
        switch route {
        case .events:      appState.route = nil; showEvents = true
        case .newEvent:    appState.route = nil; viewModel.showNewSessionSheet = true
        case .profile:     appState.route = nil; showProfile = true
        case .invitation:
            appState.route = nil
            Task {
                for _ in 0..<30 {
                    if let s = viewModel.selectedSummary { sessionForInvite = s; return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        default: break
        }
    }
}
