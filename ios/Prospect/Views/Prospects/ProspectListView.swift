// Views/Prospects/ProspectListView.swift
// The heart of the app: one event's prospects. A title, one line of numbers, search, and a
// ruled list. Refreshes itself every few seconds.
import SwiftUI

/// What the organizer can do to the event shown. Agents get none: the event belongs to the organizer.
struct EventActions {
    var edit: () -> Void
    var objectives: () -> Void
    var toggleArchive: () -> Void
    var delete: () -> Void
}

struct ProspectListView: View {
    let summary: SessionSummary
    let isReadOnly: Bool
    var onShowProfile: () -> Void
    var onShowEvents: () -> Void
    var eventActions: EventActions?

    @State private var viewModel: ProspectListViewModel
    @State private var showAddForm = false
    @State private var prospectToEdit: Prospect?
    @State private var showFilters = false
    @State private var toast: Toast?
    @State private var highlightedId: UUID?
    @FocusState private var searchFocused: Bool
    @Environment(AppState.self) private var appState

    init(summary: SessionSummary, isReadOnly: Bool, onShowProfile: @escaping () -> Void, onShowEvents: @escaping () -> Void,
         eventActions: EventActions? = nil) {
        self.summary = summary
        self.isReadOnly = isReadOnly
        self.onShowProfile = onShowProfile
        self.onShowEvents = onShowEvents
        self.eventActions = eventActions
        _viewModel = State(initialValue: ProspectListViewModel(session: summary.asSession, isReadOnly: isReadOnly))
    }

    // MARK: Derived

    private var total: Int { viewModel.prospects.count }
    private var rdvCount: Int {
        viewModel.prospects.filter { $0.statut == Statut.rdvInfo.rawValue || $0.statut == Statut.rdvAdmission.rawValue }.count
    }
    private var rate: Int { total > 0 ? Int((Double(rdvCount) / Double(total) * 100).rounded()) : 0 }

    private var groups: [(statut: Statut, prospects: [Prospect])] {
        Statut.allCases.reversed().compactMap { st in
            let items = viewModel.filteredProspects.filter { $0.statut == st.rawValue }
            return items.isEmpty ? nil : (st, items)
        }
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
        ZStack(alignment: .bottomTrailing) {
            List {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: Space.l, bottom: Space.s, trailing: Space.l))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if viewModel.isLoading && viewModel.prospects.isEmpty {
                    ForEach(0..<7, id: \.self) { _ in
                        SkeletonRow().registerRow()
                    }
                } else if viewModel.filteredProspects.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(groups, id: \.statut) { group in
                        Section {
                            ForEach(group.prospects) { prospect in
                                Button {
                                    prospectToEdit = prospect
                                } label: {
                                    ProspectRow(prospect: prospect, showsStatus: false)
                                        .padding(.horizontal, Space.s)
                                        .background(highlightedId == prospect.id ? Color.accent.opacity(0.16) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                                        .padding(.horizontal, -Space.s)
                                }
                                .id(prospect.id)
                                .buttonStyle(PressableStyle(scale: 0.995))
                                .registerRow()
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !isReadOnly {
                                        Button {
                                            Haptics.soft()
                                            Task {
                                                await viewModel.archiveProspect(prospect)
                                                toast = Toast(message: L("Prospect archived"), style: .info)
                                            }
                                        } label: {
                                            Label(L("Archive"), systemImage: "archivebox.fill")
                                        }
                                        .tint(Color.surfaceCard2)
                                    }
                                }
                            }
                        } header: {
                            StatusGroupHeader(statut: group.statut, count: group.prospects.count,
                                              onAdd: isReadOnly ? nil : { showAddForm = true })
                                .listRowInsets(EdgeInsets(top: 0, leading: Space.l, bottom: 0, trailing: Space.l))
                        }
                    }
                }

                // Room for the tab bar and add button.
                Color.clear.frame(height: 110)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 55)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .animation(.curve(0.25), value: viewModel.filteredProspects.map(\.id))
            .refreshable { await viewModel.load() }

        }
        .background(PaperBackground())
        .toast($toast)
        .sheet(isPresented: $showAddForm) {
            ProspectFormView(mode: .create(session: summary.asSession), programs: appState.programs, authorName: appState.agentNom) { saved in
                viewModel.upsertLocally(saved)
                toast = Toast(message: L("Prospect added"), style: .success)
                reveal(saved.id, proxy)
            }
            .presentationDetents([.fraction(0.64), .large])
            .presentationContentInteraction(.scrolls)
            .presentationBackground(Color.surfaceBackground)
        }
        .sheet(item: $prospectToEdit) { prospect in
            ProspectFormView(mode: .edit(prospect), programs: appState.programs, isReadOnly: isReadOnly) { saved in
                viewModel.upsertLocally(saved)
                toast = Toast(message: L("Changes saved"), style: .success)
            }
            .presentationDetents([.fraction(0.64), .large])
            .presentationContentInteraction(.scrolls)
            .presentationBackground(Color.surfaceBackground)
        }
        .sheet(isPresented: $showFilters) {
            ProspectFilterSheet(viewModel: viewModel, programs: appState.programs)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.surfaceBackground)
        }
        // Cancelled automatically when the list leaves the screen, which stops polling.
        .task { await viewModel.loadAndPoll() }
        .alert(L("Error"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: appState.route, initial: true) { _, route in handle(route) }
        }
    }

    /// Scrolls to a prospect that was just added and lights its row for a moment.
    private func reveal(_ id: UUID, _ proxy: ScrollViewProxy) {
        highlightedId = id
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.curve(0.35)) { proxy.scrollTo(id, anchor: .center) }
            try? await Task.sleep(for: .milliseconds(2600))
            withAnimation(.curve(0.5)) { if highlightedId == id { highlightedId = nil } }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            topBar
            titleBlock
            searchRow
        }
    }

    /// Floating round buttons: profile on the left, live dot and filters on the right.
    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: { Haptics.tap(); onShowProfile() }) {
                Monogram(name: appState.agentNom, size: 44)
                    .frame(width: 55, height: 55)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(L("Profile"))
            .accessibilityIdentifier("profileButton")
            Spacer()
            if appState.isAdmin {
                IconButton(systemImage: "qrcode", label: L("Invite")) { appState.route = .invitation }
                    .accessibilityIdentifier("inviteButton")
            }
            if let actions = eventActions {
                // The event's settings, right beside the filters.
                Menu {
                    Button { actions.edit() } label: { Label(L("Edit"), systemImage: "pencil") }
                    Button { actions.objectives() } label: { Label(L("Targets"), systemImage: "target") }
                    Button { actions.toggleArchive() } label: {
                        Label(summary.isArchived ? L("Unarchive") : L("Archive"), systemImage: summary.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) { actions.delete() } label: { Label(L("Delete"), systemImage: "trash") }
                } label: {
                    IconCircle(systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel(L("Settings"))
                .accessibilityIdentifier("eventSettingsButton")
            }
            IconButton(systemImage: "line.3.horizontal.decrease", label: L("Filters"), showsBadge: viewModel.hasActiveFilters) {
                showFilters = true
            }
            .accessibilityIdentifier("filterButton")
        }
        .padding(.leading, -Space.xs)
        .padding(.trailing, -Space.s)
    }

    /// The event name (tap to switch) and a single line of numbers.
    private var titleBlock: some View {
        Button(action: { Haptics.tap(); onShowEvents() }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(summary.name)
                        .font(.displayL)
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.inkTertiary)
                }
                HStack(spacing: Space.m) {
                    Text(summaryLine)
                        .font(.textSub)
                        .foregroundStyle(Color.inkSecondary)
                        .contentTransition(.numericText())
                        .animation(.curve(), value: total)
                    eventStatus
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.995))
        .accessibilityLabel(L("\(summary.name), \(summaryLine). Change \(appState.eventLabel.lowercased())"))
        .accessibilityIdentifier("eventPicker")
    }

    /// The event's state, right under its name.
    @ViewBuilder
    private var eventStatus: some View {
        if summary.statutSession == .enCours {
            Stamp(text: L("Live"), color: .accent, showsLiveDot: true)
        } else if isReadOnly {
            StatusLabel(text: summary.statutSession == .termine ? L("Finished") : L("Read-only"), color: .inkTertiary, showsDot: false)
        }
    }

    private var summaryLine: String {
        guard total > 0 else { return L("No prospects") }
        // Agents see a count only: figures and rates belong to the organizer.
        let count = L("\(total) prospects")
        guard appState.isAdmin else { return count }
        let meetings = L("\(rdvCount) meetings")
        return "\(count) · \(meetings) · \(Language.percent(rate))"
    }

    /// A quiet raised field. No outline.
    private var searchRow: some View {
        @Bindable var vm = viewModel
        return HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.inkTertiary)
            TextField(L("Search"), text: $vm.searchText)
                .font(.textBody)
                .foregroundStyle(Color.inkPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .tint(Color.accent)
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkTertiary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, Space.l)
        .frame(height: 48)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    // MARK: Empty & actions

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.hasActiveFilters || !viewModel.searchText.isEmpty {
            EmptyStateView(
                title: L("No results."),
                message: L("Nothing matches these filters."),
                actionTitle: L("Show all"),
                action: { viewModel.clearFilters(); viewModel.searchText = "" }
            )
        } else if isReadOnly {
            EmptyStateView(title: L("No prospects."), message: "")
        } else {
            EmptyStateView(
                title: L("No prospects."),
                message: L("Recorded prospects appear here."),
                actionTitle: L("Add a prospect"),
                action: { showAddForm = true }
            )
        }
    }

    // MARK: Routing (debug menu)

    private func handle(_ route: AppState.Route?) {
        switch route {
        case .newProspect:
            appState.route = nil
            if !isReadOnly { showAddForm = true }
        case .filters:
            appState.route = nil
            showFilters = true
        case .editProspect:
            appState.route = nil
            Task {
                for _ in 0..<30 {
                    if let first = viewModel.prospects.first { prospectToEdit = first; return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        default:
            break
        }
    }
}
