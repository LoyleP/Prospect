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

/// A named user state. Each one boots the app on an offline demo backend in that state.
enum DebugScenario: String, CaseIterable, Identifiable {
    case signedOutJoin, signedOutAdmin, signedOutCreateAccount
    case adminNewAccount, adminEmptyOrg, adminFull
    case agent, conseiller

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signedOutJoin:          return "Déconnecté · Rejoindre"
        case .signedOutAdmin:         return "Déconnecté · Administrateur"
        case .signedOutCreateAccount: return "Déconnecté · Créer un compte"
        case .adminNewAccount:        return "Admin · compte neuf"
        case .adminEmptyOrg:          return "Admin · organisation vide"
        case .adminFull:              return "Admin · organisation active"
        case .agent:                  return "Agent · événement en cours"
        case .conseiller:             return "Conseiller · événement en cours"
        }
    }

    var subtitle: String {
        switch self {
        case .signedOutJoin:          return "Écran de connexion, onglet code. Essayez XXXXXX (invalide) ou C-… (conseiller)"
        case .signedOutAdmin:         return "Connexion email + mot de passe (tout est accepté)"
        case .signedOutCreateAccount: return "Création de compte → onboarding organisation"
        case .adminNewAccount:        return "Connecté, aucune organisation : onboarding"
        case .adminEmptyOrg:          return "Organisation créée, sans programme ni événement"
        case .adminFull:              return "3 événements, 18 prospects, 5 programmes, équipe"
        case .agent:                  return "Rejoint avec un code agent, peut saisir"
        case .conseiller:             return "Rejoint avec un code conseiller, lecture seule"
        }
    }

    var icon: String {
        switch self {
        case .signedOutJoin:          return "number.square"
        case .signedOutAdmin:         return "person.badge.key"
        case .signedOutCreateAccount: return "person.crop.circle.badge.plus"
        case .adminNewAccount:        return "sparkles"
        case .adminEmptyOrg:          return "tray"
        case .adminFull:              return "chart.bar.doc.horizontal"
        case .agent:                  return "person.fill.checkmark"
        case .conseiller:             return "eye"
        }
    }

    var intent: AppState.LoginIntent? {
        switch self {
        case .signedOutJoin:          return .join
        case .signedOutAdmin:         return .admin
        case .signedOutCreateAccount: return .createAccount
        default:                      return nil
        }
    }

    func setup(eventLabel: String) -> DemoProspectService.Setup {
        var s = DemoProspectService.Setup(eventLabel: eventLabel)
        switch self {
        case .signedOutJoin, .signedOutAdmin, .signedOutCreateAccount:
            s.signedIn = false
        case .adminNewAccount:
            s.hasOrganization = false
        case .adminEmptyOrg:
            s.populated = false
        case .adminFull:
            break
        case .agent:
            s.identity = .participant(role: .agent, name: "Hugo Petit")
        case .conseiller:
            s.identity = .participant(role: .conseillerFormation, name: "Julien Morel")
        }
        return s
    }
}

// MARK: - Launch handling

/// Reads `-debugScenario <name>` (or the remembered scenario) before the UI is built.
enum DebugLaunch {
    static let scenarioKey = "debug.scenario"
    static let autoLaunchKey = "debug.autoLaunch"
    static let eventLabelKey = "debug.eventLabel"
    nonisolated(unsafe) static var intent: AppState.LoginIntent?

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

    static func prepare() {
        guard let scenario = requested() else { return }
        let label = UserDefaults.standard.string(forKey: eventLabelKey) ?? "Salon"
        let demo = DemoProspectService(scenario.setup(eventLabel: label))
        DemoMode.active = demo
        ProspectService.override = demo
        intent = scenario.intent
        UserDefaults.standard.set(scenario.rawValue, forKey: scenarioKey)
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
                // `-debugRoute <newProspect|editProspect|filters|events|newEvent|eventAccess|profile>`
                // opens that screen after launch.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-debugRoute"), args.indices.contains(i + 1) {
                    let routes: [String: AppState.Route] = [
                        "newProspect": .newProspect, "editProspect": .editProspect, "filters": .filters,
                        "events": .events, "newEvent": .newEvent, "eventAccess": .eventAccess, "profile": .profile,
                    ]
                    try? await Task.sleep(for: .milliseconds(1500))
                    appState.route = routes[args[i + 1]]
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
    @AppStorage(DebugLaunch.eventLabelKey) private var eventLabel = "Salon"
    @State private var toast: Toast?

    private static let labels = ["Salon", "JPO", "Événement", "Forum"]

    private var isDemo: Bool { DemoMode.active != nil }

    var body: some View {
        NavigationStack {
            List {
                modeSection
                scenariosSection
                if appState.phase == .ready { navigationSection; screensSection }
                demoDataSection
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
                Image(systemName: isDemo ? "testtube.2" : "bolt.horizontal.fill")
                    .foregroundStyle(isDemo ? Color.warning : Color.success)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDemo ? "Mode démo (hors ligne)" : "API réelle")
                        .font(.textHeadline)
                    Text(isDemo ? (DebugScenario(rawValue: lastScenario)?.title ?? "Données d'exemple") : APIClient.shared.baseURL.absoluteString)
                        .font(.textCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if isDemo {
                Button("Revenir à l'API réelle") {
                    Task { await appState.useDemo(nil); dismiss() }
                }
            }
        } header: { Text("Mode") }
        .listRowBackground(Color.surfaceCard)
    }

    private var scenariosSection: some View {
        Section {
            ForEach(DebugScenario.allCases) { scenario in
                Button {
                    Task { await apply(scenario) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: scenario.icon)
                            .foregroundStyle(Color.accent)
                            .frame(width: 28)
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
        } header: { Text("États utilisateur") } footer: {
            Text("Chaque état démarre l'app sur des données d'exemple modifiables. Rien n'est envoyé au serveur.")
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var navigationSection: some View {
        Section("Aller à") {
            ForEach([
                ("Prospects", "person.2", AppState.MainTab.prospects),
                ("Tableau de bord", "chart.bar.fill", .dashboard),
                ("Archive", "archivebox", .archive),
                ("Équipe", "building.2", .team),
            ], id: \.0) { title, icon, tab in
                Button {
                    appState.selectedTab = tab
                    dismiss()
                } label: {
                    Label(title, systemImage: icon).foregroundStyle(Color.inkPrimary)
                }
                .disabled(tab == .team && !appState.isAdmin)
            }
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var screensSection: some View {
        Section {
            ForEach([
                ("Ajouter un prospect", "person.crop.circle.badge.plus", AppState.Route.newProspect),
                ("Modifier un prospect", "pencil", .editProspect),
                ("Filtres", "line.3.horizontal.decrease.circle", .filters),
                ("Choisir un événement", "calendar", .events),
                ("Créer un événement", "calendar.badge.plus", .newEvent),
                ("Codes d'accès", "qrcode", .eventAccess),
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
                .disabled(route == .newProspect && !appState.canEditProspects)
            }
        } header: { Text("Écrans") } footer: {
            Text("Ouvre l'écran dans l'état utilisateur courant. Certains écrans sont réservés aux admins.")
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var demoDataSection: some View {
        Section {
            Picker("Nom des événements", selection: $eventLabel) {
                ForEach(Self.labels, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Relancer dans le dernier état", isOn: $autoLaunch)
        } header: { Text("Données de démo") } footer: {
            Text("Le nom des événements s'applique au prochain état choisi.")
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var toolsSection: some View {
        Section("Outils") {
            Button { toast = Toast(message: "Prospect enregistré", style: .success) } label: { Label("Toast · succès", systemImage: "checkmark.circle") }
            Button { toast = Toast(message: "Connexion impossible", style: .error) } label: { Label("Toast · erreur", systemImage: "exclamationmark.triangle") }
            Button { toast = Toast(message: "Code copié", style: .info) } label: { Label("Toast · info", systemImage: "info.circle") }
            Button { Haptics.success() } label: { Label("Haptique · succès", systemImage: "iphone.radiowaves.left.and.right") }
            Button { Haptics.error() } label: { Label("Haptique · erreur", systemImage: "iphone.radiowaves.left.and.right") }
            Button(role: .destructive) {
                AuthService.shared.clearSession()
                Task { await appState.useDemo(nil); dismiss() }
            } label: { Label("Effacer la session (Keychain)", systemImage: "key.slash") }
        }
        .foregroundStyle(Color.inkPrimary)
        .listRowBackground(Color.surfaceCard)
    }

    private var infoSection: some View {
        Section("Infos") {
            LabeledContent("API", value: APIClient.shared.baseURL.absoluteString)
            LabeledContent("Phase", value: String(describing: appState.phase))
            LabeledContent("Rôle", value: appState.currentOrganization.map { $0.role.label } ?? "—")
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        }
        .font(.textCaption)
        .listRowBackground(Color.surfaceCard)
    }

    // MARK: Actions

    private func apply(_ scenario: DebugScenario) async {
        lastScenario = scenario.rawValue
        let demo = DemoProspectService(scenario.setup(eventLabel: eventLabel))
        dismiss()
        try? await Task.sleep(for: .milliseconds(250))
        await appState.useDemo(demo, loginIntent: scenario.intent)
    }
}

#Preview {
    DebugMenuView().environment(AppState.preview())
}

#endif
