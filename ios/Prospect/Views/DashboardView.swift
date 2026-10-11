// Views/DashboardView.swift
// Stats dashboard with event switcher.
import SwiftUI
import Charts

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var shareRequest: ShareRequest?

    private enum ShareRequest: String, Identifiable {
        case prospects, dashboard
        var id: String { rawValue }
    }
    @State private var showFilters = false
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.sessions.isEmpty {
                    ContentUnavailableView(
                        "Aucune donnée",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Les statistiques apparaîtront dès qu'un \(appState.eventLabel.lowercased()) aura été créé dans l'onglet Prospects.")
                    )
                    .padding(.top, 40)
                } else {
                    if let ts = viewModel.lastUpdatedAt {
                        Text("Mis à jour à \(ts.formatted(date: .omitted, time: .shortened))")
                            .font(.geistCaption)
                            .foregroundStyle(.secondary)
                    }
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            heroCard
                            if viewModel.filterPrograms.isEmpty {
                                Divider().padding(.vertical, 24)
                                programSection
                            }
                            Divider().padding(.vertical, 24)
                            statutSection
                            if appState.isAdminOrCF && viewModel.preRegistered > 0 && viewModel.filterPrograms.isEmpty {
                                Divider().padding(.vertical, 24)
                                showNoShowSection
                            }
                            if appState.isAdmin {
                                Divider().padding(.vertical, 24)
                                closingSection
                            }
                            Divider().padding(.vertical, 24)
                            agentSection
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .themedScrollBackground()
        .groupBoxStyle(SurfaceCardGroupBoxStyle())
        .navigationTitle("Tableau de bord")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !viewModel.prospects.isEmpty {
                    Button { showFilters = true } label: {
                        Image(systemName: viewModel.hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
                if appState.canExport, viewModel.selectedSession != nil, !viewModel.prospects.isEmpty {
                    Menu {
                        Button {
                            shareRequest = .prospects
                        } label: {
                            Label("Liste des prospects (CSV)", systemImage: "person.text.rectangle")
                        }
                        Button {
                            shareRequest = .dashboard
                        } label: {
                            Label("Statistiques (CSV)", systemImage: "chart.bar")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if !viewModel.sessions.isEmpty || !viewModel.archivedSessions.isEmpty {
                    Menu {
                        ForEach(viewModel.sessions) { s in
                            Button {
                                Task { await viewModel.selectSession(s) }
                            } label: {
                                Label(s.name, systemImage: viewModel.selectedSession?.id == s.id ? "checkmark" : "")
                            }
                        }
                        if !viewModel.archivedSessions.isEmpty {
                            Menu("Archivées") {
                                ForEach(viewModel.archivedSessions) { s in
                                    Button {
                                        Task { await viewModel.selectSession(s) }
                                    } label: {
                                        Label(s.name, systemImage: viewModel.selectedSession?.id == s.id ? "checkmark" : "")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            DashboardFilterSheet(viewModel: viewModel, programs: appState.programs)
        }
        .sheet(item: $shareRequest) { request in
            if let session = viewModel.selectedSession {
                switch request {
                case .prospects:
                    ShareSheet(
                        csvData: CSVExporter.generate(
                            prospects: viewModel.filteredProspects,
                            sessionName: session.name,
                            eventLabel: appState.eventLabel,
                            programName: appState.programName
                        ),
                        fileName: csvFileName("prospects", session.name, session.date)
                    )
                case .dashboard:
                    ShareSheet(
                        csvData: DashboardCSVExporter.generate(
                            session: session.asSession,
                            total: viewModel.totalProspects,
                            byProgram: viewModel.byProgram,
                            byStatut: viewModel.byStatut,
                            byAgent: viewModel.byAgent,
                            closing: viewModel.closing,
                            programName: appState.programName
                        ),
                        fileName: csvFileName("statistiques", session.name, session.date)
                    )
                }
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
        .task {
            viewModel.programs = appState.programs
            await viewModel.loadSessions()
        }
        .refreshable { await viewModel.loadSessions() }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        GroupBox {
            VStack(alignment: .center, spacing: 8) {
                Text("\(viewModel.totalProspects)")
                    .font(.geistLargeStat)
                    .monospacedDigit()
                if let session = viewModel.selectedSession {
                    Text("\(session.name)  ·  \(session.formattedDate)")
                        .font(.geistSubheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if viewModel.totalProspects > 0 {
                    Divider().padding(.vertical, 10)
                    HStack(spacing: 0) {
                        VStack(alignment: .center, spacing: 4) {
                            Text("\(Int(viewModel.rdvRate.rounded()))%")
                                .font(.geistMonoTitle3.weight(.bold))
                            Text("Taux RDV")
                                .font(.geistCaption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 32)
                        VStack(alignment: .center, spacing: 4) {
                            Text("\(viewModel.rdvCount)")
                                .font(.geistMonoTitle3.weight(.bold))
                            Text("RDVs")
                                .font(.geistCaption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 32)
                        VStack(alignment: .center, spacing: 2) {
                            Text("\(viewModel.byStatut.first(where: { $0.statut == .rdvAdmission })?.count ?? 0)")
                                .font(.geistMonoTitle3.weight(.bold))
                            Text("Admissions")
                                .font(.geistCaption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Program donut chart

    private var programSection: some View {
        GroupBox {
                Chart(viewModel.byProgram) { item in
                    let program = appState.program(item.programId)
                    SectorMark(
                        angle: .value("Prospects", item.count),
                        innerRadius: .ratio(0.52),
                        angularInset: 1.5
                    )
                    .foregroundStyle(program?.swiftUIColor ?? Color.gray400)
                    .cornerRadius(4)
                    .annotation(position: .overlay) {
                        let pct = viewModel.totalProspects > 0
                            ? Int((Double(item.count) / Double(viewModel.totalProspects) * 100).rounded())
                            : 0
                        if pct >= 5 {
                            VStack(spacing: 1) {
                                Text("\(item.count)")
                                    .font(.geistMonoCaption.weight(.bold))
                                Text("\(pct)%")
                                    .font(.geistCaption2)
                            }
                            .foregroundStyle(program?.labelColor ?? .white)
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 320)

                // Manual legend — needed because direct .foregroundStyle() bypasses chart's auto legend
                let legendColumns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 6) {
                    ForEach(viewModel.byProgram) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.program(item.programId)?.swiftUIColor ?? Color.gray400)
                                .frame(width: 8, height: 8)
                            Text(appState.programName(item.programId))
                                .font(.geistCaption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
        }
    }

    // MARK: - Statut breakdown

    private var statutSection: some View {
        GroupBox {
            VStack(spacing: 16) {
                ForEach(viewModel.byStatut) { item in
                    HStack {
                        StatutBadge(statut: item.statut)
                        Spacer()
                        Text("\(item.count)")
                            .font(.geistMonoHeadline)
                    }
                    .opacity(item.count == 0 ? 0.35 : 1.0)
                }
            }
        }
    }

    // MARK: - Show / No-Show

    private var showNoShowSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        let showFraction = min(1.0, Double(viewModel.totalProspects) / Double(viewModel.preRegistered))
                        let showWidth    = geo.size.width * CGFloat(showFraction)
                        let noShowWidth  = geo.size.width - showWidth
                        HStack(spacing: 0) {
                            ZStack {
                                Rectangle().fill(Color.info)
                                Text("\(viewModel.totalProspects) P (\(Int((showFraction * 100).rounded()))%)")
                                    .font(.geistMonoCaption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                            }
                            .frame(width: max(0, showWidth))

                            ZStack {
                                Rectangle().fill(Color.gray300)
                                Text("\(viewModel.noShowCount) NS (\(100 - Int((showFraction * 100).rounded()))%)")
                                    .font(.geistMonoCaption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                            }
                            .frame(width: max(0, noShowWidth))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(height: 36)

                    (Text("Pré-inscrits : ").font(.geistCaption)
                    + Text("\(viewModel.preRegistered)").font(.geistMonoCaption)
                    + Text(" · No shows (NS) : ").font(.geistCaption)
                    + Text("\(viewModel.noShowCount)").font(.geistMonoCaption))
                        .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Closing

    private var closingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 24) {

                // Taux de closing RDV
                VStack(alignment: .leading, spacing: 6) {
                    Text("Taux de closing RDV")
                        .font(.geistHeadline)
                    Chart {
                        // Without targets the bar fades over the whole 0–100% range.
                        let gradientTarget = viewModel.rdvTargetHigh > 0 ? Double(viewModel.rdvTargetHigh) : 100
                        let gradientEndX = viewModel.rdvRate > 0 ? gradientTarget / viewModel.rdvRate : 1.0
                        BarMark(
                            xStart: .value("", 0.0),
                            xEnd: .value("Taux", viewModel.rdvRate),
                            y: .value("", "")
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.targetLow, Color.targetHigh],
                                startPoint: .leading,
                                endPoint: UnitPoint(x: gradientEndX, y: 0.5)
                            )
                        )
                        .cornerRadius(4)

                        if viewModel.hasRdvTargets {
                        RuleMark(x: .value("Objectif bas", Double(viewModel.rdvTargetLow)))
                            .foregroundStyle(Color.targetLow)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .annotation(position: .top, alignment: .center) {
                                Text("\(viewModel.rdvTargetLow)%")
                                    .font(.geistMonoCaption2.weight(.bold))
                                    .foregroundStyle(Color.targetLow)
                            }

                        RuleMark(x: .value("Objectif haut", Double(viewModel.rdvTargetHigh)))
                            .foregroundStyle(Color.targetHigh)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .annotation(position: .top, alignment: .center) {
                                Text("\(viewModel.rdvTargetHigh)%")
                                    .font(.geistMonoCaption2.weight(.bold))
                                    .foregroundStyle(Color.targetHigh)
                            }
                        }
                    }
                    .chartXScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisValueLabel {
                                Text("\(value.as(Int.self) ?? 0)%").font(.geistMonoCaption2)
                            }
                            AxisGridLine()
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 72)

                    (Text("\(Int(viewModel.rdvRate.rounded()))%").font(.geistMonoCaption)
                    + Text(" des prospects ont un RDV · ").font(.geistCaption)
                    + Text("\(viewModel.rdvCount)").font(.geistMonoCaption)
                    + Text(" sur ").font(.geistCaption)
                    + Text("\(viewModel.totalProspects)").font(.geistMonoCaption))
                        .foregroundStyle(.secondary)
                }

                // Advisor breakdown — grouped by program
                Divider()
                if viewModel.closingByProgram.isEmpty {
                    Text("Aucun conseiller rattaché à un programme. Assignez des programmes dans l'onglet Équipe.")
                        .font(.geistSubheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.closingByProgram, id: \.program.id) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.program.name)
                                    .font(.geistCaption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ForEach(group.items) { item in
                                    HStack(spacing: 12) {
                                        Text(item.cfNom)
                                            .font(.geistSubheadline)
                                        Spacer()
                                        Label("\(item.rdvInfo)", systemImage: "calendar")
                                            .font(.geistMonoCaption)
                                            .foregroundStyle(Color.warning)
                                        Label("\(item.rdvAdmission)", systemImage: "calendar.badge.checkmark")
                                            .font(.geistMonoCaption)
                                            .foregroundStyle(Color.success)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Agents

    private var agentSection: some View {
        GroupBox {
            if viewModel.byAgent.isEmpty {
                Text("Aucune donnée")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.byAgent) { item in
                        HStack {
                            Text(item.agentNom)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text("\(item.count)")
                                .font(.geistMonoHeadline)
                        }
                    }
                }
            }
        }
    }
}

private struct SurfaceCardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Dashboard filter sheet

private struct DashboardFilterSheet: View {
    var viewModel: DashboardViewModel
    let programs: [Program]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

#Preview("Dashboard — Admin") {
    NavigationStack {
        DashboardView()
    }
    .environment(AppState.preview(role: .admin))
}
