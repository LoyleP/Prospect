// Views/ProspectListView.swift
// Main view for an event. Polling sync, search, filters, and FAB for new prospects.
import SwiftUI

struct ProspectListView<TrailingItem: View>: View {
    let session: Session
    let isReadOnly: Bool
    let trailingItem: (_ showObjectives: @escaping () -> Void) -> TrailingItem

    @State private var viewModel: ProspectListViewModel
    @State private var showAddForm  = false
    @State private var prospectToEdit: Prospect?
    @State private var showFilters = false
    @Environment(AppState.self) private var appState

    init(session: Session, isReadOnly: Bool, @ViewBuilder trailingItem: @escaping (_ showObjectives: @escaping () -> Void) -> TrailingItem = { _ in EmptyView() }) {
        self.session      = session
        self.isReadOnly   = isReadOnly
        self.trailingItem = trailingItem
        _viewModel = State(initialValue: ProspectListViewModel(session: session, isReadOnly: isReadOnly))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
        List {
            ForEach(viewModel.filteredProspects) { prospect in
                ProspectRow(prospect: prospect)
                    .contentShape(Rectangle())
                    .onTapGesture { prospectToEdit = prospect }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isReadOnly {
                            Button(role: .destructive) {
                                Task { await viewModel.archiveProspect(prospect) }
                            } label: {
                                Label("Archiver", systemImage: "archivebox")
                            }
                        }
                    }
            }
            .themedRowBackground()
        }
        .themedListBackground()
        .safeAreaInset(edge: .bottom) {
            if !isReadOnly { Color.clear.frame(height: 72) }
        }
        .searchable(text: $viewModel.searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Rechercher un prospect…")
        .overlay {
            if viewModel.filteredProspects.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Aucun prospect",
                    systemImage: "person.slash",
                    description: Text(
                        viewModel.hasActiveFilters
                        ? "Aucun résultat pour ces filtres."
                        : "Appuyez sur + pour ajouter un prospect."
                    )
                )
            }
        }

        // FAB
        if !isReadOnly {
            if #available(iOS 26.0, *) {
                Button { showAddForm = true } label: {
                    Label("Nouveau prospect", systemImage: "plus")
                        .font(.geistBody.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accent, in: Capsule())
                }
                .glassEffect(in: Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            } else {
                Button { showAddForm = true } label: {
                    Label("Nouveau prospect", systemImage: "plus")
                        .font(.geistBody.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accent)
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        } // ZStack
        .themedNavigationBar()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: viewModel.hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                trailingItem({})
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(viewModel: viewModel, programs: appState.programs)
        }
        .fullScreenCover(isPresented: $showAddForm) {
            NavigationStack {
                ProspectFormView(
                    mode: .create(session: session),
                    programs: appState.programs
                ) { newProspect in
                    viewModel.upsertLocally(newProspect)
                }
            }
        }
        .navigationDestination(item: $prospectToEdit) { prospect in
            ProspectFormView(
                mode: .edit(prospect),
                programs: appState.programs,
                isReadOnly: isReadOnly
            ) { updated in
                viewModel.upsertLocally(updated)
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .refreshable { await viewModel.load() }
        // Cancelled automatically when the list leaves the screen, which stops polling.
        .task { await viewModel.loadAndPoll() }
    }
}

// MARK: - Filter sheet

private struct FilterSheet: View {
    var viewModel: ProspectListViewModel
    let programs: [Program]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pillGroup {
                        ForEach(Statut.allCases) { s in
                            Toggle(s.rawValue, isOn: Binding(
                                get: { viewModel.filterStatuts.contains(s) },
                                set: { viewModel.filterStatuts.toggle(member: s, isOn: $0) }
                            ))
                            .toggleStyle(FilterToggleStyle())
                        }
                    }
                    Divider()
                    pillGroup {
                        ForEach(programs) { p in
                            Toggle(p.name, isOn: Binding(
                                get: { viewModel.filterPrograms.contains(p.id) },
                                set: { viewModel.filterPrograms.toggle(member: p.id, isOn: $0) }
                            ))
                            .toggleStyle(FilterToggleStyle())
                        }
                    }
                    Divider()
                    pillGroup {
                        ForEach(NiveauActuel.allCases) { n in
                            Toggle(n.rawValue, isOn: Binding(
                                get: { viewModel.filterNiveaux.contains(n) },
                                set: { viewModel.filterNiveaux.toggle(member: n, isOn: $0) }
                            ))
                            .toggleStyle(FilterToggleStyle())
                        }
                    }
                    if !viewModel.agentNames.isEmpty {
                        Divider()
                        pillGroup {
                            ForEach(viewModel.agentNames, id: \.self) { name in
                                Toggle(name, isOn: Binding(
                                    get: { viewModel.filterAgents.contains(name) },
                                    set: { viewModel.filterAgents.toggle(member: name, isOn: $0) }
                                ))
                                .toggleStyle(FilterToggleStyle())
                            }
                        }
                    }
                }
            }
            .themedScrollBackground()
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.hasActiveFilters {
                        Button("Réinitialiser", role: .destructive) {
                            viewModel.clearFilters()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func pillGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        PillFlowLayout(spacing: 8) {
            content()
        }
        .padding(16)
    }
}

