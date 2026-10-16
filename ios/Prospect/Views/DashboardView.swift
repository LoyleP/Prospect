// Views/DashboardView.swift
// The event report: one page of numbered sections, ruled like a ledger. Numbers first,
// ranked bars rather than pies, and a chart of when the rush happened.
import SwiftUI
import Charts

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var shareRequest: ShareRequest?
    @State private var showFilters = false
    @State private var showEvents = false
    @State private var showDetails = false
    @Environment(AppState.self) private var appState

    private enum ShareRequest: String, Identifiable {
        case prospects, dashboard
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                topBar

                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if viewModel.sessions.isEmpty {
                    EmptyStateView(
                        title: L("Nothing to count."),
                        message: L("Figures appear once prospects are recorded for the current session.")
                    )
                    .padding(.horizontal, -Space.gutter)
                } else {
                    titleBlock
                    importsBanner
                        .animation(.curve(Motion.standard), value: viewModel.selectedSession?.session.importsComplete)
                    if viewModel.prospects.isEmpty && !viewModel.isLoading {
                        EmptyStateView(title: L("No prospects."), message: L("No figures for this session yet."))
                            .padding(.horizontal, -Space.gutter)
                    } else {
                        overview
                        pipeline
                        if viewModel.filterPrograms.isEmpty { programs }
                        detailsToggle
                        if showDetails {
                            VStack(alignment: .leading, spacing: Space.xl) {
                                arrivals
                                if appState.isAdmin && viewModel.preRegistered > 0 && viewModel.filterPrograms.isEmpty { attendance }
                                members
                            }
                            .transition(.rise)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, 110)
        }
        .background(PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await viewModel.loadSessions() }
        .sheet(isPresented: $showFilters) {
            DashboardFilterSheet(viewModel: viewModel, programs: appState.programs)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.surfaceBackground)
        }
        .sheet(isPresented: $showEvents) {
            EventPickerSheet(
                summaries: viewModel.sessions + viewModel.archivedSessions,
                selectedId: viewModel.selectedSession?.id,
                isAdmin: false,
                eventLabel: appState.eventLabel,
                onSelect: { s in Task { await viewModel.selectSession(s) } },
                onCreate: {}, onEdit: { _ in }, onAccess: { _ in }, onObjectives: { _ in },
                onToggleArchive: { _ in }, onDelete: { _ in }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.surfaceBackground)
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
        .alert(L("Error"), isPresented: Binding(
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
        // Every tab stays alive: refresh when this one is opened (a nearby import or "Imports terminés" happened elsewhere).
        .onChange(of: appState.selectedTab) { _, tab in
            guard tab == .dashboard else { return }
            Task { viewModel.programs = appState.programs; await viewModel.loadSessions() }
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(spacing: Space.m) {
            Spacer()
            if !viewModel.prospects.isEmpty {
                IconButton(systemImage: "line.3.horizontal.decrease", label: L("Filters"), showsBadge: viewModel.hasActiveFilters) { showFilters = true }
            }
            if appState.canExport, viewModel.selectedSession != nil, !viewModel.prospects.isEmpty {
                Menu {
                    Button { shareRequest = .prospects } label: { Label(L("Prospect list (CSV)"), systemImage: "person.text.rectangle") }
                    Button { shareRequest = .dashboard } label: { Label(L("Statistics (CSV)"), systemImage: "chart.bar") }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCard2, in: Circle())
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Export"))
            }
        }
        .frame(minHeight: 42)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let session = viewModel.selectedSession {
            VStack(alignment: .leading, spacing: Space.s) {
                Button {
                    Haptics.tap()
                    showEvents = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(session.name)
                            .font(.displayL)
                            .foregroundStyle(Color.inkPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.995))
            }
        }
    }

    // MARK: - Sections

    private var overview: some View {
        section("01", L("Overview")) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(viewModel.totalProspects)")
                            .font(.numeral(88))
                            .foregroundStyle(Color.inkPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        label("prospects")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Space.m) {
                        bigStat("\(viewModel.rdvCount)", L("meetings"))
                        bigStat(Language.percent(Int(viewModel.rdvRate.rounded())), L("meeting rate"))
                    }
                }
                if viewModel.hasRdvTargets {
                    TargetGauge(rate: viewModel.rdvRate, low: viewModel.rdvTargetLow, high: viewModel.rdvTargetHigh)
                }
            }
        }
    }

    private var pipeline: some View {
        section("02", L("Progress")) {
            let maxCount = max(1, viewModel.byStatut.map(\.count).max() ?? 1)
            VStack(spacing: Space.l) {
                ForEach(viewModel.byStatut) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusStamp(statut: item.statut)
                            Spacer()
                            Text("\(item.count)")
                                .font(.figureHeadline)
                                .foregroundStyle(Color.inkPrimary)
                        }
                        Bar(fraction: Double(item.count) / Double(maxCount), color: item.statut.color)
                    }
                    .opacity(item.count == 0 ? 0.45 : 1)
                }
            }
        }
    }

    private var programs: some View {
        section("03", L("Programs")) {
            let items = viewModel.byProgram
            let maxCount = max(1, items.map(\.count).max() ?? 1)
            VStack(spacing: Space.l) {
                ForEach(items) { item in
                    let program = appState.program(item.programId)
                    let objective = program.flatMap { viewModel.selectedSession?.programObjectives[$0.id] }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: Space.s) {
                            Circle().fill(program?.swiftUIColor ?? Color.inkTertiary).frame(width: 9, height: 9)
                            Text(appState.programName(item.programId))
                                .font(.textSub.weight(.semibold))
                                .foregroundStyle(Color.inkPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(objective.map { "\(item.count) / \($0)" } ?? "\(item.count)")
                                .font(.figureHeadline)
                                .foregroundStyle(Color.inkPrimary)
                        }
                        let scale = max(objective ?? maxCount, 1)   // bars fill toward the objective when there is one
                        Bar(fraction: Double(item.count) / Double(scale), color: program?.swiftUIColor ?? Color.inkTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var arrivals: some View {
        if viewModel.arrivals.count > 1 {
            section("04", L("Traffic")) {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let peak = viewModel.peakHour, peak.count > 0 {
                        let peakCount = L("\(peak.count) prospects")
                        Text(L("Peak at \(Language.hour(peak.hour)): \(peakCount)."))
                            .font(.textSub)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Chart(viewModel.arrivals) { item in
                        BarMark(x: .value("Hour", Language.hour(item.hour)), y: .value("Prospects", item.count))
                            .foregroundStyle(item.hour == viewModel.peakHour?.hour ? Color.accent : Color.inkPrimary)
                            .cornerRadius(2)
                            .annotation(position: .top, spacing: 3) {
                                if item.count > 0 {
                                    Text("\(item.count)")
                                        .font(.textCaption.weight(.medium))
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().font(.labelCaption2).foregroundStyle(Color.inkTertiary)
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
    }

    private var attendance: some View {
        section("05", L("Attendance")) {
            let registered = viewModel.prospects.count
            let expected = viewModel.preRegistered
            let fraction = min(1, Double(registered) / Double(max(expected, 1)))
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(registered)")
                        .font(.numeral(40))
                        .foregroundStyle(Color.inkPrimary)
                    Text(L("of \(expected) pre-registered"))
                        .font(.textSub)
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                    Text(Language.percent(Int((fraction * 100).rounded())))
                        .font(.figureHeadline)
                        .foregroundStyle(Color.inkPrimary)
                }
                Bar(fraction: fraction, color: .inkPrimary)

            }
        }
    }

    /// Organizer: until every agent's file is imported and confirmed, the numbers are incomplete.
    @ViewBuilder
    private var importsBanner: some View {
        if appState.isAdmin, let s = viewModel.selectedSession, !s.session.importsComplete {
            Button {
                Haptics.tap()
                appState.selectedTab = .exchange
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "tray.and.arrow.down").foregroundStyle(Color.warning)
                    Text(L("Incomplete imports")).font(.textBody.weight(.medium)).foregroundStyle(Color.inkPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.inkTertiary)
                }
                .padding(.horizontal, Space.l)
                .frame(minHeight: 55)
                .background(Color.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))
            .accessibilityIdentifier("importsBanner")
            .transition(.drop)
        }
    }

    private var closing: some View {
        section("06", "Closing") {
            if viewModel.closingByProgram.isEmpty {
                Text(L("No advisor assigned to a program."))
                    .font(.textSub)
                    .foregroundStyle(Color.inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(viewModel.closingByProgram, id: \.program.id) { group in
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack(spacing: Space.s) {
                                Circle().fill(group.program.swiftUIColor).frame(width: 9, height: 9)
                                label(group.program.name)
                            }
                            ForEach(group.items) { item in
                                HStack {
                                    Text(item.cfNom)
                                        .font(.textSub)
                                        .foregroundStyle(Color.inkPrimary)
                                    Spacer()
                                    countChip("info", item.rdvInfo, Statut.rdvInfo.color)
                                    countChip("admission", item.rdvAdmission, Statut.rdvAdmission.color)
                                }
                                .padding(.vertical, 4)
                                Rule()
                            }
                        }
                    }
                }
            }
        }
    }

    private var members: some View {
        section("07", L("Team")) {
            let items = viewModel.byAgent
            let maxCount = max(1, items.map(\.count).max() ?? 1)
            VStack(spacing: Space.m) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: Space.m) {
                        Text(String(format: "%02d", index + 1))
                            .font(.figure(12, weight: .semibold))
                            .foregroundStyle(Color.inkTertiary)
                            .frame(width: 22, alignment: .leading)
                        Text(item.agentNom)
                            .font(.textSub)
                            .foregroundStyle(Color.inkPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        Bar(fraction: Double(item.count) / Double(maxCount), color: .inkPrimary)
                            .frame(width: 90)
                        Text("\(item.count)")
                            .font(.figureHeadline)
                            .foregroundStyle(Color.inkPrimary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(title)
                .font(.textSub.weight(.medium))
                .foregroundStyle(Color.inkTertiary)
            content()
        }
    }

    /// Everything beyond the essentials stays folded away until asked for.
    private var detailsToggle: some View {
        Button {
            Haptics.selection()
            withAnimation(.curve(0.2)) { showDetails.toggle() }
        } label: {
            HStack {
                Text(showDetails ? L("Fewer details") : L("More details"))
                    .font(.textSub.weight(.semibold))
                Spacer()
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color.inkPrimary)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.textCaption.weight(.medium))
            .foregroundStyle(Color.inkTertiary)
    }

    private func bigStat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.numeral(34))
                .foregroundStyle(Color.inkPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            label(caption)
        }
    }

    private func countChip(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)")
                .font(.figureHeadline)
                .foregroundStyle(Color.inkPrimary)
            Text(title)
                .font(.textCaption)
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.leading, Space.m)
    }

    private func percent(_ part: Int, of total: Int) -> String {
        total > 0 ? Language.percent(Int((Double(part) / Double(total) * 100).rounded())) : "–"
    }
}

// MARK: - Bar & gauge

/// A flat horizontal bar on a hairline track.
struct Bar: View {
    let fraction: Double
    var color: Color = .inkPrimary
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.rule)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.curve(0.35), value: fraction)
        .accessibilityHidden(true)
    }
}

/// The RDV rate against its target band, on a 0–100 % ruler.
struct TargetGauge: View {
    let rate: Double
    let low: Int
    let high: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.rule).frame(height: 8)
                    // Target band
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.success.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.success, lineWidth: 1))
                        .frame(width: CGFloat(max(0, high - low)) / 100 * w, height: 18)
                        .offset(x: CGFloat(low) / 100 * w)
                    // Current rate
                    Capsule().fill(Color.inkPrimary).frame(width: min(100, rate) / 100 * w, height: 8)
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack {
                Text("0 %")
                Spacer()
                Text(L("Target \(low)–\(Language.percent(high))"))
                    .foregroundStyle(Color.success)
                Spacer()
                Text("100 %")
            }
            .font(.labelCaption2)
            .foregroundStyle(Color.inkTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Meeting rate \(Int(rate.rounded())) percent, target between \(low) and \(high) percent"))
    }
}

// MARK: - Filter sheet

private struct DashboardFilterSheet: View {
    var viewModel: DashboardViewModel
    let programs: [Program]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack {
                    Text(L("Filters"))
                        .font(.displayS)
                        .foregroundStyle(Color.inkPrimary)
                    Spacer()
                    if viewModel.hasActiveFilters {
                        Button(L("Reset")) { Haptics.tap(); withAnimation(.curve()) { viewModel.clearFilters() } }
                            .buttonStyle(.link)
                    }
                }
                if !programs.isEmpty {
                    group(L("Program")) {
                        ForEach(programs) { p in
                            ChoiceChip(title: p.name, isSelected: viewModel.filterPrograms.contains(p.id), tint: p.swiftUIColor) {
                                viewModel.filterPrograms.toggle(member: p.id, isOn: !viewModel.filterPrograms.contains(p.id))
                            }
                        }
                    }
                }
                group(L("Status")) {
                    ForEach(Statut.allCases) { s in
                        ChoiceChip(title: s.rawValue, isSelected: viewModel.filterStatuts.contains(s), tint: s.color) {
                            viewModel.filterStatuts.toggle(member: s, isOn: !viewModel.filterStatuts.contains(s))
                        }
                    }
                }
                group(L("Current level")) {
                    ForEach(NiveauActuel.allCases) { n in
                        ChoiceChip(title: n.rawValue, isSelected: viewModel.filterNiveaux.contains(n)) {
                            viewModel.filterNiveaux.toggle(member: n, isOn: !viewModel.filterNiveaux.contains(n))
                        }
                    }
                }
                if viewModel.agentNames.count > 1 {
                    group(L("Recorded by")) {
                        ForEach(viewModel.agentNames, id: \.self) { name in
                            ChoiceChip(title: name, isSelected: viewModel.filterAgents.contains(name)) {
                                viewModel.filterAgents.toggle(member: name, isOn: !viewModel.filterAgents.contains(name))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text(L("View \(viewModel.totalProspects) prospects"))
                    .contentTransition(.numericText())
            }
            .buttonStyle(.primary)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
        .presentationDragIndicator(.visible)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(.textSub.weight(.medium))
                .foregroundStyle(Color.inkTertiary)
            PillFlowLayout(spacing: Space.s) { content() }
        }
    }
}

#Preview("Dashboard — Organisateur") {
    NavigationStack { DashboardView() }
        .environment(AppState.preview(.organizerFull))
}
