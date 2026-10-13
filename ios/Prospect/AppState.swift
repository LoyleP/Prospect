// AppState.swift
// Global observable state. There is no account and no server: the phone either has an identity
// (a name and a role: organizer or agent) or it is still at onboarding. Events and prospects live in
// the LocalStore; this object only mirrors what the screens need.
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Phase: Equatable {
        case onboarding
        case ready
    }

    var phase: Phase
    /// This phone's workspace (a name and a role). Built from the stored identity.
    var currentOrganization: Organization?
    var programs: [Program] = []
    var selectedTab: MainTab = .prospects
    /// Which onboarding choice to show first (set by the debug menu).
    var onboardingIntent: OnboardingIntent?
    /// Bumped to rebuild the whole UI tree (new view models) when the store is swapped.
    var epoch = 0
    /// The language of the app: English unless the person chose another one.
    private(set) var language: AppLanguage = Language.current

    /// A screen to open from outside its view (used by the debug menu and by incoming links).
    var route: Route?
    /// An invitation opened from a link or scanned, waiting for the person to choose a name.
    var pendingInvitation: Invitation?
    /// What the last imported file did, shown once as a toast.
    var importMessage: String?

    enum Route: Equatable { case newProspect, editProspect, filters, events, newEvent, profile, invitation }
    enum MainTab: Hashable { case prospects, dashboard, archive, exchange }
    enum OnboardingIntent: Equatable { case organize, join }

    private(set) var store: LocalStore
    private(set) var exchange: EventExchange

    init(store: LocalStore = EventExchange.current.store, exchange: EventExchange = .current) {
        self.store = store
        self.exchange = exchange
        let identity = store.read { $0.identity }
        self.phase = identity == nil ? .onboarding : .ready
        refresh()
    }

    // MARK: - Derived

    var role: Role { currentOrganization?.role ?? .agent }
    /// The organizer: creates events, hands out invitations, collects what agents send.
    var isAdmin: Bool { role == .admin }
    var canExport: Bool { isAdmin }
    /// A conseiller only reads what the organizer sends: no recording, no editing.
    var isConseiller: Bool { role == .conseillerFormation }
    var canEditProspects: Bool { !isConseiller }

    /// The person's display name, written on every prospect they record.
    var agentNom: String { currentOrganization?.displayName ?? "" }
    var eventLabel: String { currentOrganization?.eventLabel ?? L("Event") }

    func program(_ id: UUID?) -> Program? {
        guard let id else { return nil }
        return programs.first { $0.id == id }
    }

    func programName(_ id: UUID?) -> String {
        program(id)?.name ?? L("No program")
    }

    // MARK: - Language

    /// Every screen is rebuilt, so all text (including Strings computed along the way) is read again in the new language.
    func setLanguage(_ new: AppLanguage) {
        guard new != language else { return }
        Language.current = new
        language = new
        epoch += 1
    }

    // MARK: - Identity

    /// Mirrors the store into the screens' state.
    func refresh() {
        let (identity, deviceId, programs) = store.read { ($0.identity, $0.deviceId, $0.programs) }
        self.programs = programs.sorted { $0.sortOrder < $1.sortOrder }
        if let identity {
            currentOrganization = Organization(
                id: deviceId, name: "", eventLabel: identity.eventLabel, role: identity.role,
                displayName: identity.displayName, programIds: []
            )
            phase = .ready
        } else {
            currentOrganization = nil
            phase = .onboarding
        }
    }

    /// Onboarding, organizer side.
    func startOrganizing(name: String, eventLabel: String) {
        store.write { $0.identity = StoredIdentity(displayName: name, role: .admin, eventLabel: eventLabel) }
        refresh()
    }

    /// Onboarding, agent or conseiller side: the name, then the invitation that was scanned or opened.
    func startAsAgent(name: String, invitation: Invitation, role: Role = .agent) throws {
        store.write { $0.identity = StoredIdentity(displayName: name, role: role, eventLabel: invitation.eventLabel) }
        try exchange.join(invitation)
        pendingInvitation = nil
        refresh()
        EndReminder.schedule(for: invitation)
    }

    func updateIdentity(displayName: String? = nil, eventLabel: String? = nil) {
        store.write { state in
            if let displayName { state.identity?.displayName = displayName }
            if let eventLabel { state.identity?.eventLabel = eventLabel }
        }
        refresh()
    }

    func reloadPrograms() async {
        programs = (try? await ProspectService.current.fetchPrograms()) ?? programs
    }

    /// An agent joins another event with a new invitation while already set up.
    func join(_ invitation: Invitation) throws {
        try exchange.join(invitation)
        pendingInvitation = nil
        refresh()
        EndReminder.schedule(for: invitation)
    }

    // MARK: - Reset

    /// Wipes this phone: identity, events, prospects and keys. Used by "Réinitialiser cet appareil".
    func resetDevice() {
        let ids = store.read { $0.events.map(\.id) }
        ids.forEach { exchange.keys.remove(for: $0) }
        EndReminder.cancelAll()
        LiveActivityManager.shared.end()
        store.reset()
        selectedTab = .prospects
        refresh()
        epoch += 1
    }

    // MARK: - Incoming links and files

    /// `prospect://join?i=…` (an invitation) or a `.prospects` file (an agent's end-of-day file).
    func handleIncoming(_ url: URL) {
        if let invitation = Invitation(url: url) {
            if phase == .ready, role == .agent {
                do {
                    try join(invitation)
                    importMessage = L("Joined: \(invitation.name)")
                    epoch += 1
                } catch { importMessage = error.localizedDescription }
            } else if phase == .ready {
                importMessage = L("This invitation opens on an agent's phone.")
            } else {
                pendingInvitation = invitation
                onboardingIntent = .join
            }
            return
        }
        guard url.pathExtension == Handover.fileExtension else { return }
        guard phase == .ready, isAdmin else {
            importMessage = L("Only the organizer can import a file.")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let outcome = try exchange.importHandover(try Data(contentsOf: url))
            importMessage = Self.message(for: outcome)
            epoch += 1
        } catch {
            importMessage = error.localizedDescription
        }
    }

    static func message(for outcome: ImportOutcome) -> String {
        let m = outcome.merge
        if m.added == 0 && m.updated == 0 { return L("\(outcome.agentName): nothing new (already imported).") }
        var parts = [L("\(m.added) added")]
        if m.updated > 0 { parts.append(L("\(m.updated) updated")) }
        return L("\(outcome.agentName): \(parts.joined(separator: ", "))")
    }

    // MARK: - Demo store (debug)

    /// Swaps the whole app onto another store (demo data) and restarts from the state it describes.
    func useStore(_ store: LocalStore, keys: KeyVault, service: ProspectServiceProtocol?, onboardingIntent: OnboardingIntent? = nil) {
        self.store = store
        self.exchange = EventExchange(store: store, keys: keys)
        EventExchange.override = self.exchange
        ProspectService.override = service
        self.onboardingIntent = onboardingIntent
        selectedTab = .prospects
        refresh()
        epoch += 1
    }
}
