// ProspectTests/LocalFirstTests.swift
// The part of the app that carries the privacy promise: local storage, the invitation, the encrypted
// handover and the merge. Two phones are simulated with two separate stores.
import CryptoKit
import XCTest
@testable import Prospect

final class LocalFirstTests: XCTestCase {

    // MARK: Helpers

    private struct Phone {
        let store: LocalStore
        let keys: MemoryKeyVault
        let service: ProspectService
        let exchange: EventExchange
    }

    private func phone(role: Role, name: String) -> Phone {
        let keys = MemoryKeyVault()
        let store = LocalStore(url: nil, initial: LocalState(identity: StoredIdentity(displayName: name, role: role, eventLabel: "Salon")))
        return Phone(store: store, keys: keys, service: ProspectService(store: store, keys: keys), exchange: EventExchange(store: store, keys: keys))
    }

    private func input(_ first: String, _ last: String, email: String? = nil, phone: String = "0612345678", clientId: UUID? = nil) -> ProspectInput {
        ProspectInput(prenom: first, nom: last, email: email ?? "\(first.lowercased())@exemple.fr", telephone: phone,
                      programId: nil, niveauActuel: "Terminale", statut: "Curieux", notes: nil, clientId: clientId)
    }

    // MARK: Store

    func testStorePersistsToDiskAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = LocalStore(url: url)
        first.write { $0.identity = StoredIdentity(displayName: "Léa", role: .agent, eventLabel: "JPO") }
        let second = LocalStore(url: url)
        XCTAssertEqual(second.read { $0.identity?.displayName }, "Léa")
        second.reset()
        XCTAssertNil(LocalStore(url: url).read { $0.identity })
    }

    // MARK: Invitation

    func testInvitationRoundTripsAndStaysSmall() throws {
        let programs = (0..<6).map { Invitation.ProgramInfo(id: UUID(), name: "Programme numéro \($0)", color: "#3366E6", order: $0) }
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let original = Invitation(eventId: UUID(), name: "Salon de l'étudiant", date: "2026-11-14", endsAt: end, organizerName: "Camille Martin",
                                  publicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
                                  eventLabel: "Salon", programs: programs)
        let decoded = try XCTUnwrap(Invitation(url: original.url))
        XCTAssertEqual(decoded, original)
        XCTAssertLessThan(original.url.absoluteString.count, 800, "a typical invitation (6 programs) stays easy to scan")
        XCTAssertNil(Invitation(text: "https://example.com"))
        XCTAssertNil(Invitation(text: "prospect://join?i=not-valid"))
    }

    // MARK: Handover encryption

    func testHandoverIsReadableOnlyByTheOrganizer() throws {
        let event = UUID()
        let organizer = Curve25519.KeyAgreement.PrivateKey()
        let stranger = Curve25519.KeyAgreement.PrivateKey()
        let payload = Handover.Payload(agentId: UUID(), agentName: "Hugo", sentAt: Date(timeIntervalSince1970: 1_800_000_000),
                                       prospects: [TestData.prospect(sessionId: event)])
        let data = try Handover.seal(payload, eventId: event, organizerPublicKey: organizer.publicKey.rawRepresentation.base64EncodedString())

        let (envelope, opened) = try Handover.open(data, privateKey: organizer, eventId: event)
        XCTAssertEqual(opened, payload)
        XCTAssertEqual(envelope.count, 1)

        XCTAssertThrowsError(try Handover.open(data, privateKey: stranger, eventId: event)) {
            XCTAssertEqual($0 as? Handover.HandoverError, .cannotDecrypt)
        }
        XCTAssertThrowsError(try Handover.open(data, privateKey: organizer, eventId: UUID())) {
            XCTAssertEqual($0 as? Handover.HandoverError, .wrongEvent)
        }
        // Nothing readable in the file: a visitor's name never appears in clear text.
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Durand"))
    }

    func testTamperedHandoverIsRejected() throws {
        let event = UUID()
        let organizer = Curve25519.KeyAgreement.PrivateKey()
        let payload = Handover.Payload(agentId: UUID(), agentName: "Hugo", sentAt: Date(), prospects: [])
        var data = try Handover.seal(payload, eventId: event, organizerPublicKey: organizer.publicKey.rawRepresentation.base64EncodedString())
        var envelope = try XCTUnwrap(Handover.envelope(of: data))
        var box = try XCTUnwrap(Data(base64Encoded: envelope.box))
        box[box.count - 1] ^= 0xFF
        envelope.box = box.base64EncodedString()
        data = try JSONEncoder().encode(envelope)
        XCTAssertThrowsError(try Handover.open(data, privateKey: organizer, eventId: event))
    }

    // MARK: Merge

    func testMergeAddsNewKeepsLatestAndIsIdempotent() {
        var event = StoredEvent(id: UUID(), name: "Salon", date: "2026-11-14", endsAt: nil, status: .enCours, isArchived: false,
                                preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0, programObjectives: [:], createdAt: "2026-11-14T08:00:00.000Z",
                                organizerName: "Camille", organizerPublicKey: "", isOrganizer: true, prospects: [], receipts: [],
                                lastSentAt: nil, lastSentCount: 0)
        let a = TestData.prospect(sessionId: event.id, prenom: "Léa")
        var edited = a; edited.statut = Statut.rdvInfo.rawValue; edited.updatedAt = "2026-11-14T11:00:00.000Z"
        let payload1 = Handover.Payload(agentId: UUID(), agentName: "Hugo", sentAt: Date(), prospects: [a])
        XCTAssertEqual(HandoverMerge.merge(payload1, into: &event).added, 1)
        XCTAssertEqual(HandoverMerge.merge(payload1, into: &event), MergeResult(added: 0, updated: 0, unchanged: 1), "same file twice: no change")
        XCTAssertEqual(event.prospects.count, 1)

        let payload2 = Handover.Payload(agentId: payload1.agentId, agentName: "Hugo", sentAt: Date(), prospects: [edited])
        XCTAssertEqual(HandoverMerge.merge(payload2, into: &event).updated, 1)
        XCTAssertEqual(event.prospects.first?.statut, Statut.rdvInfo.rawValue)
        XCTAssertEqual(event.receipts.count, 1, "one receipt per agent")
    }

    func testDuplicateGroupsByEmailOrPhone() {
        let s = UUID()
        let a = TestData.prospect(sessionId: s, prenom: "Léa")
        var b = TestData.prospect(sessionId: s, prenom: "Lea"); b.email = "LEA@exemple.fr "
        var c = TestData.prospect(sessionId: s, prenom: "Hugo"); c.email = "hugo@exemple.fr"; c.telephone = "0699999999"
        var d = TestData.prospect(sessionId: s, prenom: "Hugues"); d.email = "autre@exemple.fr"; d.telephone = "+33 6 99 99 99 99"
        let groups = HandoverMerge.duplicateGroups(in: [a, b, c, d])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.count)), [2])
    }

    // MARK: Service

    func testOrganizerCreatesEventAndAgentCannot() async throws {
        let organizer = phone(role: .admin, name: "Camille")
        let created = try await organizer.service.createSession(name: "Salon", date: Date())
        XCTAssertEqual(created.statutSession, .enCours)
        XCTAssertNotNil(organizer.keys.privateKey(for: created.id), "the event key stays on the organizer's phone")

        let agent = phone(role: .agent, name: "Hugo")
        do {
            _ = try await agent.service.createSession(name: "Non", date: Date())
            XCTFail("an agent cannot create events")
        } catch { XCTAssertEqual(error as? ServiceError, .notAllowed) }
    }

    func testProspectLifecycleAndIdempotentCreate() async throws {
        let p = phone(role: .admin, name: "Camille")
        let event = try await p.service.createSession(name: "Salon", date: Date())
        let id = UUID()
        let first = try await p.service.createProspect(sessionId: event.id, input("Léa", "Durand", clientId: id))
        let again = try await p.service.createProspect(sessionId: event.id, input("Léa", "Durand", clientId: id))
        XCTAssertEqual(first.id, again.id)
        let afterCreate = try await p.service.fetchProspects(sessionId: event.id)
        XCTAssertEqual(afterCreate.count, 1, "a double tap never creates two")

        try await p.service.archiveProspect(id: id)
        let active = try await p.service.fetchProspects(sessionId: event.id)
        let archived = try await p.service.fetchArchivedProspects()
        XCTAssertTrue(active.isEmpty)
        XCTAssertEqual(archived.count, 1)

        try await p.service.restoreProspect(id: id)
        let restored = try await p.service.fetchProspects(sessionId: event.id)
        let stats = try await p.service.fetchMyStats()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(stats.prospects, 1)
    }

    // MARK: Whole flow, two phones

    func testInvitationHandoverAndImportBetweenTwoPhones() async throws {
        let organizer = phone(role: .admin, name: "Camille")
        _ = try await organizer.service.createProgram(name: "Informatique", color: nil)
        let event = try await organizer.service.createSession(name: "Salon", date: Date())
        _ = try await organizer.service.createProspect(sessionId: event.id, input("Camille", "Orga"))

        // The agent joins by "scanning" the invitation.
        let agent = phone(role: .agent, name: "Hugo")
        let invitation = try XCTUnwrap(Invitation(url: try organizer.exchange.invitation(for: event.id).url))
        try agent.exchange.join(invitation)
        let agentPrograms = try await agent.service.fetchPrograms()
        let agentEvents = try await agent.service.fetchSessionSummaries()
        XCTAssertEqual(agentPrograms.map(\.name), ["Informatique"])
        XCTAssertEqual(agentEvents.first?.name, "Salon")
        XCTAssertThrowsError(try agent.exchange.invitation(for: event.id), "only the organizer can invite")

        // The agent records, then sends.
        _ = try await agent.service.createProspect(sessionId: event.id, input("Léa", "Durand"))
        _ = try await agent.service.createProspect(sessionId: event.id, input("Noé", "Lambert", phone: "0788888888"))
        let file = try agent.exchange.handoverFile(for: event.id)
        XCTAssertEqual(file.count, 2)
        XCTAssertTrue(file.fileName.hasSuffix(".prospects"))

        // The organizer imports it (twice, to prove it is safe).
        let outcome = try organizer.exchange.importHandover(file.data)
        XCTAssertEqual(outcome.merge.added, 2)
        XCTAssertEqual(outcome.agentName, "Hugo")
        XCTAssertEqual(try organizer.exchange.importHandover(file.data).merge.added, 0)
        let all = try await organizer.service.fetchProspects(sessionId: event.id)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.agentNom)), ["Camille", "Hugo"])

        // A file for this event cannot be opened by another organizer.
        let other = phone(role: .admin, name: "Autre")
        XCTAssertThrowsError(try other.exchange.importHandover(file.data)) {
            XCTAssertEqual($0 as? ExchangeError, .unknownEvent)
        }
        // An agent's phone cannot import at all.
        XCTAssertThrowsError(try agent.exchange.importHandover(file.data)) {
            XCTAssertEqual($0 as? ExchangeError, .notOrganizer)
        }
    }

    func testMarkSentRemembersWhenAndHowMany() async throws {
        let organizer = phone(role: .admin, name: "Camille")
        let event = try await organizer.service.createSession(name: "Salon", date: Date())
        let agent = phone(role: .agent, name: "Hugo")
        try agent.exchange.join(try organizer.exchange.invitation(for: event.id))
        agent.exchange.markSent(eventId: event.id, count: 4, at: Date(timeIntervalSince1970: 1_800_000_000))
        let stored = agent.store.read { $0.events.first }
        XCTAssertEqual(stored?.lastSentCount, 4)
        XCTAssertNotNil(stored?.lastSentAt)
    }
}
