// Views/SessionListView.swift
// Prospects tab — shows ProspectListView for the selected event, with a calendar event picker.
// Events are named by the organization (appState.eventLabel).
import SwiftUI

struct SessionListView: View {
    @State private var viewModel = SessionListViewModel()
    @State private var showProfile = false
    @State private var sessionForObjectives: SessionSummary?
    @State private var sessionForAccess: SessionSummary?
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.summaries.isEmpty {
                ProgressView()
            } else if viewModel.summaries.isEmpty {
                ContentUnavailableView {
                    Label("Rien pour l'instant", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(appState.isAdmin
                         ? "Créez votre premier \(appState.eventLabel.lowercased()) avec le bouton +."
                         : "Un administrateur doit d'abord créer un \(appState.eventLabel.lowercased()).")
                } actions: {
                    if appState.isAdmin {
                        Button("Créer : \(appState.eventLabel)") { viewModel.showNewSessionSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else if let selected = viewModel.selectedSummary {
                ProspectListView(
                    session: selected.asSession,
                    isReadOnly: selected.statutSession != .enCours || !appState.canEditProspects
                ) { _ in
                    if appState.isAdmin {
                        Button { sessionForObjectives = selected } label: {
                            Image(systemName: "target")
                            .accessibilityLabel("Objectifs")
                        }
                    }
                    if appState.isAdmin {
                    Menu {
                        if appState.isAdmin {
                            Button {
                                sessionForAccess = selected
                            } label: {
                                Label("Codes d'accès", systemImage: "qrcode")
                            }
                            Button {
                                viewModel.beginEdit(selected)
                            } label: {
                                Label("Modifier", systemImage: "pencil")
                            }
                            Button {
                                Task { await viewModel.toggleArchive(selected) }
                            } label: {
                                Label(
                                    selected.isArchived ? "Désarchiver" : "Archiver",
                                    systemImage: selected.isArchived ? "archivebox.fill" : "archivebox"
                                )
                            }
                            Divider()
                            Button(role: .destructive) {
                                viewModel.sessionToDelete = selected
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Actions")
                    }
                    .accessibilityIdentifier("eventMenu")
                    }
                }
                .id(selected.id)
            }
        }
        .themedScrollBackground()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showProfile = true } label: {
                    Label(appState.agentNom, systemImage: "person.circle")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("profileButton")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Session picker
                if !viewModel.activeSummaries.isEmpty || !viewModel.archivedSummaries.isEmpty {
                    Menu {
                        if appState.isAdmin {
                            Button {
                                viewModel.showNewSessionSheet = true
                            } label: {
                                Label("Créer : \(appState.eventLabel)", systemImage: "plus")
                            }
                            Divider()
                        }
                        ForEach(viewModel.activeSummaries) { s in
                            Button {
                                viewModel.selectedSummary = s
                            } label: {
                                Label(s.name, systemImage: viewModel.selectedSummary?.id == s.id ? "checkmark" : "")
                            }
                        }
                        if !viewModel.archivedSummaries.isEmpty {
                            Menu("Archivées") {
                                ForEach(viewModel.archivedSummaries) { s in
                                    Button {
                                        viewModel.selectedSummary = s
                                    } label: {
                                        Label(s.name, systemImage: viewModel.selectedSummary?.id == s.id ? "checkmark" : "")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                            .accessibilityLabel(appState.eventLabel)
                    }
                    .accessibilityIdentifier("eventPicker")
                } else if appState.isAdmin {
                    Button {
                        viewModel.showNewSessionSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationDestination(item: $sessionForObjectives) { session in
            ObjectivesView(session: session)
                .onDisappear { Task { await viewModel.load() } }
        }
        .sheet(item: $sessionForAccess) { summary in
            EventAccessView(summary: summary) { _ in Task { await viewModel.load() } }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $viewModel.showNewSessionSheet) {
            newSessionSheet
        }
        .sheet(item: $viewModel.sessionToEdit) { _ in
            editSessionSheet
        }
        .alert(
            "Supprimer « \(viewModel.sessionToDelete?.name ?? "") » ?",
            isPresented: Binding(
                get: { viewModel.sessionToDelete != nil },
                set: { if !$0 { viewModel.sessionToDelete = nil } }
            )
        ) {
            Button("Supprimer", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Annuler", role: .cancel) {
                viewModel.sessionToDelete = nil
            }
        } message: {
            Text("Tous les prospects associés seront également supprimés. Cette action est irréversible.")
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var newSessionSheet: some View {
        NavigationStack {
            Form {
                Section(appState.eventLabel) {
                    TextField("Nom (ex. \(appState.eventLabel) mars 2027)", text: $viewModel.newSessionName)
                    DatePicker(
                        "Date",
                        selection: $viewModel.newSessionDate,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                }
                .themedRowBackground()
            }
            .themedListBackground()
            .themedNavigationBar()
            .navigationTitle("Créer : \(appState.eventLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { viewModel.showNewSessionSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task { await viewModel.createSession() }
                    }
                    .disabled(!viewModel.canCreate)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var editSessionSheet: some View {
        NavigationStack {
            Form {
                Section(appState.eventLabel) {
                    TextField("Nom", text: $viewModel.editSessionName)
                    DatePicker(
                        "Date",
                        selection: $viewModel.editSessionDate,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                }
                .themedRowBackground()
                Section("Statut") {
                    Picker("Statut", selection: $viewModel.editSessionStatut) {
                        ForEach(SessionStatut.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .themedRowBackground()
            }
            .themedListBackground()
            .themedNavigationBar()
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { viewModel.sessionToEdit = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task { await viewModel.commitEdit() }
                    }
                    .disabled(!viewModel.canUpdate)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
