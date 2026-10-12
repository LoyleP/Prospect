// Debug/DebugMenu.swift
// A developer-only menu to jump into any user state or flow without a network, an account or
// real data. Compiled out of Release builds.
//
// Open it with the floating button (draggable, visible on every screen incl. login/onboarding),
// by shaking the device, or by launching with `-debugScenario <name>` / `-debugMenu`.
import SwiftUI

extension View {
    /// Attaches the debug menu in Debug builds; does nothing in Release.
    @ViewBuilder func debugMenu() -> some View {
        #if DEBUG
        modifier(DebugMenuModifier())
        #else
        self
        #endif
    }
}

#if DEBUG

// MARK: - Scenarios

/// A named phone state. Each one starts the app on in-memory demo data: nothing touches the real store.
enum DebugScenario: String, CaseIterable, Identifiable {
    case fresh, freshOrganize, freshJoin, organizerEmpty, organizerFull, agentFull

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fresh:          return "Premier lancement"
        case .freshOrganize:  return "Premier lancement · Organiser"
        case .freshJoin:      return "Premier lancement · Rejoindre"
        case .organizerEmpty: return "Organisateur · aucun événement"
        case .organizerFull:  return "Organisateur · événement en cours"
        case .agentFull:      return "Agent · événement en cours"
        }
    }

    var subtitle: String {
        switch self {
        case .fresh:          return "Écran de choix, aucune donnée"
        case .freshOrganize:  return "Formulaire d'organisateur"
        case .freshJoin:      return "Scanner ou coller une invitation"
        case .organizerEmpty: return "Identité créée, sans programme ni événement"
        case .organizerFull:  return "3 événements, 18 prospects, 5 programmes, 1 envoi reçu"
        case .agentFull:      return "Événement rejoint, 6 prospects à envoyer"
        }
    }

    var icon: String {
        switch self {
        case .fresh, .freshOrganize, .freshJoin: return "sparkles"
        case .organizerEmpty:                    return "tray"
        case .organizerFull:                     return "tray.and.arrow.down"
        case .agentFull:                         return "paperplane"
        }
    }

    var kind: DemoSeed.Kind {
        switch self {
        case .fresh, .freshOrganize, .freshJoin: return .fresh
        case .organizerEmpty:                    return .organizerEmpty
        case .organizerFull:                     return .organizerFull
        case .agentFull:                         return .agentFull
        }
    }

    var intent: AppState.OnboardingIntent? {
        switch self {
        case .freshOrganize: return .organize
        case .freshJoin:     return .join
        default:             return nil
        }
    }
}

// MARK: - Launch handling

/// Reads `-debugScenario <name>` (or the remembered scenario) before the UI is built.
enum DebugLaunch {
    static let scenarioKey = "debug.scenario"
    static let autoLaunchKey = "debug.autoLaunch"
    nonisolated(unsafe) static var active: DebugScenario?

    static func requested() -> DebugScenario? {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-debugScenario"), args.indices.contains(i + 1),
           let scenario = DebugScenario(rawValue: args[i + 1]) {
            return scenario
        }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: autoLaunchKey), let raw = defaults.string(forKey: scenarioKey) {
            return DebugScenario(rawValue: raw)
        }
        return nil
    }

    @MainActor
    static func apply(to state: AppState) {
        guard let scenario = requested() else { return }
        start(scenario, on: state)
    }

    @MainActor
    static func start(_ scenario: DebugScenario, on state: AppState) {
        let seeded = DemoSeed.make(scenario.kind)
        state.useStore(seeded.store, keys: seeded.keys, service: seeded.service, onboardingIntent: scenario.intent)
        active = scenario
        UserDefaults.standard.set(scenario.rawValue, forKey: scenarioKey)
    }
}

extension DebugLaunch {
    /// Imports a file as if the agent Sofia Rossi had sent it to this organizer. Returns the toast text.
    @MainActor
    static func simulateHandover(on appState: AppState) throws -> String {
        let events = appState.store.read { $0.events }
        guard let event = events.first(where: { $0.isOrganizer && $0.status == .enCours }) ?? events.first(where: \.isOrganizer) else {
            throw ExchangeError.unknownEvent
        }
        let outcome = try appState.exchange.importHandover(try DemoSeed.simulatedHandover(for: event))
        appState.epoch += 1
        return AppState.message(for: outcome)
    }

    /// Fills the event this agent joined with fictional prospects, to push the nearby transfer to its limits.
    /// They all use `@mock.test` addresses so `removeMockProspects` can take them out again.
    @MainActor
    static func addMockProspects(count: Int, on appState: AppState) throws -> String {
        let firsts = ["Léa", "Hugo", "Inès", "Noé", "Jade", "Lucas", "Emma", "Tom", "Manon", "Louis", "Chloé", "Gabin", "Zoé", "Adam", "Lina", "Nathan", "Eva", "Théo", "Maya", "Rayan"]
        let lasts = ["Durand", "Bernard", "Moreau", "Lambert", "Fournier", "Girard", "Roux", "Blanc", "Garnier", "Faure", "Mercier", "Lopez", "Henry", "Perrin", "Colin", "Vidal", "Caron", "Marchand", "Bertrand", "Meyer"]
        let levels = ["< Terminale", "Terminale", "Bac +1", "Bac +2", "Bac +3"]
        let statuts = [Statut.curieux, .interesse, .rdvInfo, .rdvAdmission].map(\.rawValue)
        let note = "Rencontré(e) sur le stand, intéressé(e) par une alternance en informatique et par les portes ouvertes de mars. À rappeler en priorité."
        return try appState.store.write { state in
            guard let identity = state.identity,
                  let i = state.events.firstIndex(where: { !$0.isOrganizer && !$0.isArchived }) else { throw ExchangeError.unknownEvent }
            let event = state.events[i]
            let programs = state.programs
            let stamp = ProspectService.iso()
            let start = event.prospects.filter { $0.email.hasSuffix("@mock.test") }.count
            for n in 0..<count {
                let k = start + n
                state.events[i].prospects.append(Prospect(
                    id: UUID(), sessionId: event.id, prenom: firsts[k % firsts.count], nom: lasts[(k / firsts.count + k) % lasts.count],
                    email: "prospect\(k)@mock.test", telephone: String(format: "06 %02d %02d %02d %02d", k % 100, (k / 7) % 100, (k / 13) % 100, (k / 17) % 100),
                    programId: programs.isEmpty ? nil : programs[k % programs.count].id, niveauActuel: levels[k % levels.count],
                    statut: statuts[k % statuts.count], notes: k % 3 == 0 ? note : nil, createdBy: state.deviceId,
                    agentNom: identity.displayName, createdAt: stamp, updatedAt: stamp, deletedAt: nil))
            }
            return "\(count) prospects ajoutés à \(event.name)"
        }
    }

    @MainActor
    static func removeMockProspects(on appState: AppState) -> String {
        let removed = appState.store.write { state -> Int in
            var removed = 0
            for i in state.events.indices {
                let before = state.events[i].prospects.count
                state.events[i].prospects.removeAll { $0.email.hasSuffix("@mock.test") }
                removed += before - state.events[i].prospects.count
            }
            return removed
        }
        return "\(removed) prospects fictifs supprimés"
    }
}

// MARK: - Triggers

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
    }
}

struct DebugMenuModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            // The floating button lives in its own window (see DebugOverlay), so it is visible on
            // every screen, including login, onboarding and over sheets. Installed once.
            .onAppear { DebugOverlay.shared.install(appState: appState) }
            .task {
                // `-debugRoute <newProspect|editProspect|filters|events|newEvent|invitation|profile>`
                // opens that screen after launch.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-debugRoute"), args.indices.contains(i + 1) {
                    let routes: [String: AppState.Route] = [
                        "newProspect": .newProspect, "editProspect": .editProspect, "filters": .filters,
                        "events": .events, "newEvent": .newEvent, "invitation": .invitation, "profile": .profile,
                    ]
                    try? await Task.sleep(for: .milliseconds(1500))
                    appState.route = routes[args[i + 1]]
                }
            }
            .task {
                // `-debugSimulateHandover` imports a fake agent file at launch (screenshots).
                if ProcessInfo.processInfo.arguments.contains("-debugSimulateHandover") {
                    try? await Task.sleep(for: .milliseconds(700))
                    _ = try? DebugLaunch.simulateHandover(on: appState)
                }
            }
            .task {
                // `-debugMenu` opens the menu at launch (handy for screenshots and demos).
                if ProcessInfo.processInfo.arguments.contains("-debugMenu") {
                    try? await Task.sleep(for: .milliseconds(900))
                    DebugOverlay.shared.presentMenu()
                }
            }
            // Shaking the device still opens it too.
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                DebugOverlay.shared.presentMenu()
            }
    }
}

// MARK: - Menu

struct DebugMenuView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DebugLaunch.scenarioKey) private var lastScenario = ""
    @AppStorage(DebugLaunch.autoLaunchKey) private var autoLaunch = false
    @State private var toast: Toast?

    private var isDemo: Bool { DebugLaunch.active != nil }

    var body: some View {
        NavigationStack {
            List {
                modeSection
                scenariosSection
                if appState.phase == .ready { navigationSection; screensSection; exchangeSection; mockSection }
                toolsSection
                infoSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.surfaceBackground)
            .navigationTitle("Menu debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .toast($toast)
        }
        .accessibilityIdentifier("debugMenu")
    }

    // MARK: Sections

    private var modeSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: isDemo ? "testtube.2" : "iphone")
                    .foregroundStyle(isDemo ? Color.warning : Color.success)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDemo ? "Mode démo (mémoire)" : "Données réelles de ce téléphone").font(.textHeadline)
                    Text(isDemo ? (DebugLaunch.active?.title ?? "Données d'exemple") : "Stockage local chiffré")
                        .font(.textCaption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if isDemo {
                Button("Revenir aux données réelles") {
                    DebugLaunch.active = nil
                    UserDefaults.standard.removeObject(forKey: DebugLaunch.scenarioKey)
                    appState.useStore(.shared, keys: KeychainKeyVault(), service: nil)
                    EventExchange.override = nil
                    dismiss()
                }
            }
        } header: { Text("Mode") }
        .listRowBackground(Color.surfaceCard)
    }

    private var scenariosSection: some View {
        Section {
            ForEach(DebugScenario.allCases) { scenario in
                Button {
                    lastScenario = scenario.rawValue
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        DebugLaunch.start(scenario, on: appState)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: scenario.icon).foregroundStyle(Color.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.title).font(.textSub.weight(.semibold)).foregroundStyle(Color.inkPrimary)
                            Text(scenario.subtitle).font(.textCaption).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if isDemo && lastScenario == scenario.rawValue {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                        }
                    }
                }
            }
        } header: { Text("États du téléphone") } footer: {
            Text("Chaque état démarre l'app sur des données d'exemple en mémoire. Les vraies données ne sont pas touchées.")
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var navigationSection: some View {
        Section("Aller à") {
            ForEach([
                ("Prospects", "person.2", AppState.MainTab.prospects),
                ("Statistiques", "chart.bar.fill", .dashboard),
                ("Archive", "archivebox", .archive),
                (appState.isAdmin ? "Collecte" : "Envoi", "tray.and.arrow.down", .exchange),
            ].filter { appState.isAdmin || $0.2 != .dashboard }, id: \.0) { title, icon, tab in
                Button {
                    appState.selectedTab = tab
                    dismiss()
                } label: {
                    Label(title, systemImage: icon).foregroundStyle(Color.inkPrimary)
                }
            }
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var screensSection: some View {
        Section("Écrans") {
            ForEach([
                ("Ajouter un prospect", "person.crop.circle.badge.plus", AppState.Route.newProspect),
                ("Modifier un prospect", "pencil", .editProspect),
                ("Filtres", "line.3.horizontal.decrease.circle", .filters),
                ("Choisir un événement", "calendar", .events),
                ("Créer un événement", "calendar.badge.plus", .newEvent),
                ("Invitation (QR)", "qrcode", .invitation),
                ("Profil", "person.crop.circle", .profile),
            ], id: \.0) { title, icon, route in
                Button {
                    appState.selectedTab = .prospects
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        appState.route = route
                    }
                } label: {
                    Label(title, systemImage: icon).foregroundStyle(Color.inkPrimary)
                }
            }
        }
        .listRowBackground(Color.surfaceCard)
    }

    /// Lets one phone test the whole handover: simulate an agent sending their file to this organizer.
    @ViewBuilder
    private var exchangeSection: some View {
        if appState.isAdmin {
            Section {
                Button {
                    simulateHandover()
                } label: {
                    Label("Simuler l'envoi d'un agent", systemImage: "tray.and.arrow.down").foregroundStyle(Color.inkPrimary)
                }
            } header: { Text("Collecte") } footer: {
                Text("Crée un fichier chiffré à la clé de l'événement affiché dans l'onglet Collecte, avec 2 prospects déjà connus (doublons) et 3 nouveaux, puis l'importe.")
            }
            .listRowBackground(Color.surfaceCard)
        }
    }

    /// An agent's phone: bulk fictional prospects to test how much the nearby transfer can carry.
    @ViewBuilder
    private var mockSection: some View {
        if !appState.isAdmin {
            Section {
                ForEach([50, 100, 250, 500], id: \.self) { count in
                    Button {
                        addMock(count)
                    } label: {
                        Label("Ajouter \(count.formatted(.number.locale(Locale(identifier: "fr_FR")))) prospects", systemImage: "plus.circle").foregroundStyle(Color.inkPrimary)
                    }
                }
                Button {
                    toast = Toast(message: DebugLaunch.removeMockProspects(on: appState), style: .success)
                    appState.epoch += 1
                } label: {
                    Label("Supprimer les prospects fictifs", systemImage: "trash").foregroundStyle(Color.error)
                }
            } header: { Text("Données fictives") } footer: {
                Text("Ajoute des prospects (@mock.test) à l'événement rejoint, pour tester un gros envoi. Le bouton du bas les retire.")
            }
            .listRowBackground(Color.surfaceCard)
        }
    }

    private func addMock(_ count: Int) {
        do {
            toast = Toast(message: try DebugLaunch.addMockProspects(count: count, on: appState), style: .success)
            appState.epoch += 1
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
        }
    }

    private var toolsSection: some View {
        Section("Outils") {
            Button { toast = Toast(message: "Prospect ajouté", style: .success) } label: { Label("Toast · succès", systemImage: "checkmark.circle") }
            Button { toast = Toast(message: "Envoi impossible", style: .error) } label: { Label("Toast · erreur", systemImage: "exclamationmark.triangle") }
            Button { toast = Toast(message: "Lien copié", style: .info) } label: { Label("Toast · info", systemImage: "info.circle") }
            Button { Haptics.success() } label: { Label("Haptique · succès", systemImage: "iphone.radiowaves.left.and.right") }
            Toggle("Relancer dans le dernier état", isOn: $autoLaunch)
            Button(role: .destructive) {
                appState.resetDevice()
                dismiss()
            } label: { Label("Réinitialiser cet appareil", systemImage: "trash") }
        }
        .foregroundStyle(Color.inkPrimary)
        .listRowBackground(Color.surfaceCard)
    }

    private var infoSection: some View {
        Section("Infos") {
            LabeledContent("Phase", value: String(describing: appState.phase))
            LabeledContent("Rôle", value: appState.currentOrganization.map { $0.role == .admin ? "Organisateur" : "Agent" } ?? "—")
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        }
        .font(.textCaption)
        .listRowBackground(Color.surfaceCard)
    }

    // MARK: Actions

    private func simulateHandover() {
        do {
            toast = Toast(message: try DebugLaunch.simulateHandover(on: appState), style: .success)
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
        }
    }
}

#Preview {
    DebugMenuView().environment(AppState.preview())
}

#endif
