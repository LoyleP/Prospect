// AppState.swift
// Global observable state: who is signed in (an admin account, or a participant who joined
// one event with its code), which organization they're working in, their role there,
// and that organization's programs.
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Phase: Equatable {
        case loading            // signed in, fetching /me
        case signedOut
        case needsOrganization  // admin account that belongs to no organization yet
        case ready
    }

    var phase: Phase
    var email: String?
    var userId: UUID?
    /// Set when this device joined a single event with a code (agent or conseiller).
    var participantEvent: SessionSummary?
    var organizations: [Organization] = []
    var currentOrganization: Organization?
    var programs: [Program] = []
    var previewRole: Role?
    var loadError: String?
    var selectedTab: MainTab = .prospects
    /// Which login tab to open first (set by the debug menu).
    var loginIntent: LoginIntent?
    /// Bumped to rebuild the whole UI tree (new view models) when the backend is swapped.
    var epoch = 0

    /// A screen to open from outside its view (used by the debug menu).
    var route: Route?

    enum Route: Equatable { case newProspect, editProspect, filters, events, newEvent, profile, eventAccess }
    enum MainTab: Hashable { case prospects, dashboard, archive, team }
    enum LoginIntent: Equatable { case join, admin, createAccount }

    /// Set only by tests and previews; otherwise the live (or demo) service is used.
    @ObservationIgnored private let injectedService: ProspectServiceProtocol?
    @ObservationIgnored private var service: ProspectServiceProtocol { injectedService ?? ProspectService.current }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var expiryObserver: NSObjectProtocol?
    private static let lastOrganizationKey = "lastOrganizationId"

    // MARK: - Derived

    var role: Role { currentOrganization?.role ?? .agent }
    var effectiveRole: Role { previewRole ?? role }
    var isAdmin: Bool { effectiveRole == .admin }
    var isAdminOrCF: Bool { effectiveRole == .admin || effectiveRole == .conseillerFormation }
    var canExport: Bool { isAdminOrCF }
    /// Advisors (CF) are read-only on prospects.
    var canEditProspects: Bool { effectiveRole != .conseillerFormation }
    var isParticipant: Bool { participantEvent != nil }

    /// The member's display name in the current organization.
    var agentNom: String { currentOrganization?.displayName ?? "" }
    /// What the current organization calls its events.
    var eventLabel: String { currentOrganization?.eventLabel ?? "Événement" }

    func program(_ id: UUID?) -> Program? {
        guard let id else { return nil }
        return programs.first { $0.id == id }
    }

    func programName(_ id: UUID?) -> String {
        program(id)?.name ?? "Sans programme"
    }

    // MARK: - Lifecycle

    init(service: ProspectServiceProtocol? = nil, defaults: UserDefaults = .standard) {
        self.injectedService = service
        self.defaults = defaults
        self.phase = AuthService.shared.isSignedIn ? .loading : .signedOut
        expiryObserver = NotificationCenter.default.addObserver(
            forName: AuthService.sessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetToSignedOut() }
        }
    }

    /// Loads the user's organizations and enters the last one used.
    func bootstrap() async {
        guard AuthService.shared.isSignedIn else { phase = .signedOut; return }
        loadError = nil
        do {
            switch try await service.fetchMe() {
            case .participant(_, let org, let event):
                participantEvent = event
                organizations = [org]
                await enter(org)
            case .admin(let user, let orgs):
                participantEvent = nil
                email = user.email
                userId = user.id
                organizations = orgs
                let lastId = defaults.string(forKey: Self.lastOrganizationKey).flatMap(UUID.init(uuidString:))
                if let org = organizations.first(where: { $0.id == lastId }) ?? organizations.first {
                    await enter(org)
                } else {
                    currentOrganization = nil
                    phase = .needsOrganization
                }
            }
        } catch let error as APIError where error.status == 401 {
            resetToSignedOut()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func selectOrganization(_ org: Organization) async {
        previewRole = nil
        await enter(org)
    }

    func createOrganization(name: String, eventLabel: String) async throws {
        await add(try await service.createOrganization(name: name, eventLabel: eventLabel))
    }

    /// Joins an existing organization as co-admin with its admin code.
    func joinOrganization(adminCode: String) async throws {
        await add(try await service.joinOrganization(adminCode: adminCode))
    }

    private func add(_ org: Organization) async {
        organizations.removeAll { $0.id == org.id }
        organizations.append(org)
        organizations.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        await enter(org)
    }

    /// Applies an organization edit (name, event label, own display name or programs).
    func apply(_ org: Organization) {
        if let idx = organizations.firstIndex(where: { $0.id == org.id }) { organizations[idx] = org }
        if currentOrganization?.id == org.id { currentOrganization = org }
    }

    func reloadPrograms() async {
        do {
            programs = try await service.fetchPrograms()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func signOut() async {
        await AuthService.shared.logout()
        resetToSignedOut()
    }

    private func enter(_ org: Organization) async {
        ProspectService.shared.organizationId = org.id
        currentOrganization = org
        defaults.set(org.id.uuidString, forKey: Self.lastOrganizationKey)
        programs = (try? await service.fetchPrograms()) ?? []
        phase = .ready
    }

    private func resetToSignedOut() {
        LiveActivityManager.shared.end()
        ProspectService.shared.organizationId = nil
        organizations = []
        currentOrganization = nil
        programs = []
        previewRole = nil
        email = nil
        userId = nil
        participantEvent = nil
        phase = .signedOut
    }

    // MARK: - Demo backend

    /// Swaps the whole app onto an offline demo backend (or back to the live API with `nil`)
    /// and restarts from the state that backend describes.
    func useDemo(_ demo: DemoProspectService?, loginIntent: LoginIntent? = nil) async {
        DemoMode.active = demo
        ProspectService.override = demo
        resetToSignedOut()
        self.loginIntent = loginIntent
        selectedTab = .prospects
        epoch += 1
        #if DEBUG
        DebugOverlay.shared.refreshBadge()
        #endif
        if AuthService.shared.isSignedIn {
            phase = .loading
            await bootstrap()
        }
    }

    // MARK: - Previews

    /// Preview-only state backed by seeded demo data; never touches the network or the Keychain.
    static func preview(nom: String = "Camille Martin", role: Role = .admin, eventLabel: String = "Salon") -> AppState {
        let identity: DemoProspectService.Identity = role == .admin ? .admin(name: nom) : .participant(role: role, name: nom)
        let demo = DemoProspectService(.init(identity: identity, eventLabel: eventLabel))
        let s = AppState(service: demo)
        let org = Organization(id: DemoProspectService.orgId, name: "Atelier Horizon", eventLabel: eventLabel, role: role, displayName: nom, programIds: [], adminCode: role == .admin ? "K7M2QX" : nil)
        s.organizations = [org]
        s.currentOrganization = org
        s.programs = demo.previewPrograms
        s.phase = .ready
        return s
    }
}
