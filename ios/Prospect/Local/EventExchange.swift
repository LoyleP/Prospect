// Local/EventExchange.swift
// Everything that moves an event between phones: the invitation (organizer → agent), the end-of-day
// file (agent → organizer) and its import. No network involved.
import CryptoKit
import Foundation

enum ExchangeError: LocalizedError, Equatable {
    case noIdentity, notOrganizer, unknownEvent, notAnInvitation, notAHandover, notAnEventData, wrongEvent, cannotDecrypt, keyMissing

    var errorDescription: String? {
        switch self {
        case .noIdentity:      return "Choisissez d'abord votre nom."
        case .notOrganizer:    return "Seul l'organisateur de cet événement peut faire cela."
        case .unknownEvent:    return "Cet événement n'existe pas sur ce téléphone."
        case .notAnInvitation: return "Ce code n'est pas une invitation Prospect."
        case .notAHandover:    return "Ce fichier n'est pas un envoi Prospect."
        case .notAnEventData:  return "Ces données ne sont pas valides."
        case .wrongEvent:      return "Ce fichier appartient à un autre événement."
        case .cannotDecrypt:   return "Impossible de lire ce fichier : il n'est pas destiné à cet appareil."
        case .keyMissing:      return "La clé de cet événement est introuvable sur ce téléphone."
        }
    }
}

struct ImportOutcome: Equatable {
    let eventName: String
    let agentName: String
    let count: Int
    let merge: MergeResult
}

struct HandoverFile {
    let data: Data
    let fileName: String
    let count: Int
}

final class EventExchange: @unchecked Sendable {
    static let shared = EventExchange(store: .shared, keys: KeychainKeyVault())
    /// The demo exchange when the debug menu swapped the store, the real one otherwise.
    nonisolated(unsafe) static var override: EventExchange?
    static var current: EventExchange { override ?? shared }

    let store: LocalStore
    let keys: KeyVault

    init(store: LocalStore, keys: KeyVault) {
        self.store = store
        self.keys = keys
    }

    // MARK: Invitation (organizer → agent)

    func invitation(for eventId: UUID) throws -> Invitation {
        try store.read { state in
            guard let identity = state.identity else { throw ExchangeError.noIdentity }
            guard let e = state.events.first(where: { $0.id == eventId }) else { throw ExchangeError.unknownEvent }
            guard e.isOrganizer else { throw ExchangeError.notOrganizer }
            return Invitation(
                eventId: e.id, name: e.name, date: e.date, endsAt: e.endsAt, organizerName: e.organizerName,
                publicKey: e.organizerPublicKey, eventLabel: identity.eventLabel,
                programs: state.programs.sorted { $0.sortOrder < $1.sortOrder }
                    .map { .init(id: $0.id, name: $0.name, color: $0.color, order: $0.sortOrder) }
            )
        }
    }

    /// Creates (or refreshes) the event on this phone from an invitation. Existing prospects are kept.
    @discardableResult
    func join(_ invitation: Invitation) throws -> UUID {
        try store.write { state in
            guard state.identity != nil else { throw ExchangeError.noIdentity }
            for info in invitation.programs {
                if let i = state.programs.firstIndex(where: { $0.id == info.id }) {
                    state.programs[i].name = info.name
                    state.programs[i].color = info.color
                    state.programs[i].sortOrder = info.order
                } else {
                    state.programs.append(Program(id: info.id, name: info.name, color: info.color, sortOrder: info.order))
                }
            }
            if let i = state.events.firstIndex(where: { $0.id == invitation.eventId }) {
                guard !state.events[i].isOrganizer else { return invitation.eventId }
                state.events[i].name = invitation.name
                state.events[i].date = invitation.date
                state.events[i].endsAt = invitation.endsAt
            } else {
                state.events.append(StoredEvent(
                    id: invitation.eventId, name: invitation.name, date: invitation.date, endsAt: invitation.endsAt,
                    status: .enCours, isArchived: false, preRegistered: 0, rdvTargetLow: 0, rdvTargetHigh: 0,
                    programObjectives: [:], createdAt: ProspectService.iso(), organizerName: invitation.organizerName,
                    organizerPublicKey: invitation.publicKey, isOrganizer: false, prospects: [], receipts: [],
                    lastSentAt: nil, lastSentCount: 0, importsComplete: true
                ))
            }
            return invitation.eventId
        }
    }

    // MARK: Handover (agent → organizer)

    /// Everything this phone recorded for the event, encrypted to the organizer.
    func handoverFile(for eventId: UUID, now: Date = Date()) throws -> HandoverFile {
        let (payload, event) = try store.read { state -> (Handover.Payload, StoredEvent) in
            guard let identity = state.identity else { throw ExchangeError.noIdentity }
            guard let e = state.events.first(where: { $0.id == eventId }) else { throw ExchangeError.unknownEvent }
            let mine = e.prospects.filter { $0.createdBy == state.deviceId || e.isOrganizer }
            return (Handover.Payload(agentId: state.deviceId, agentName: identity.displayName, sentAt: now, prospects: mine), e)
        }
        let data = try Handover.seal(payload, eventId: eventId, organizerPublicKey: event.organizerPublicKey)
        let safe = { (s: String) in s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-") }
        return HandoverFile(data: data, fileName: "\(safe(event.name))_\(safe(payload.agentName)).\(Handover.fileExtension)",
                            count: payload.prospects.count)
    }

    func markSent(eventId: UUID, count: Int, at date: Date = Date()) {
        store.write { state in
            guard let i = state.events.firstIndex(where: { $0.id == eventId }) else { return }
            state.events[i].lastSentAt = date
            state.events[i].lastSentCount = count
        }
    }

    // MARK: Import (organizer)

    func setImportsComplete(eventId: UUID, _ complete: Bool) {
        store.write { state in
            if let i = state.events.firstIndex(where: { $0.id == eventId && $0.isOrganizer }) {
                state.events[i].importsComplete = complete
            }
        }
    }

    /// Reads which event a file belongs to, without decrypting it.
    func eventId(ofHandover data: Data) -> UUID? { Handover.envelope(of: data)?.event }

    func importHandover(_ data: Data, now: Date = Date()) throws -> ImportOutcome {
        guard let envelope = Handover.envelope(of: data) else { throw ExchangeError.notAHandover }
        let known = store.read { $0.events.first { $0.id == envelope.event } }
        guard let event = known else { throw ExchangeError.unknownEvent }
        guard event.isOrganizer else { throw ExchangeError.notOrganizer }
        guard let key = keys.privateKey(for: event.id) else { throw ExchangeError.keyMissing }
        let payload: Handover.Payload
        do {
            payload = try Handover.open(data, privateKey: key, eventId: event.id).1
        } catch Handover.HandoverError.wrongEvent {
            throw ExchangeError.wrongEvent
        } catch Handover.HandoverError.notAHandover {
            throw ExchangeError.notAHandover
        } catch {
            throw ExchangeError.cannotDecrypt
        }
        let merge: MergeResult = store.write { state in
            guard let i = state.events.firstIndex(where: { $0.id == event.id }) else { return MergeResult() }
            let result = HandoverMerge.merge(payload, into: &state.events[i], now: now)
            // New data arrived: the organizer has to confirm again that nothing else is missing.
            if result.added > 0 || result.updated > 0 { state.events[i].importsComplete = false }
            return result
        }
        return ImportOutcome(eventName: event.name, agentName: payload.agentName, count: payload.prospects.count, merge: merge)
    }

    // MARK: Conseiller (organizer → conseiller)

    /// What the organizer hands a conseiller: every active prospect of the event, as it stands now.
    struct EventData: Codable, Equatable, Sendable {
        var eventId: UUID
        var sentAt: Date
        var prospects: [Prospect]
    }

    func eventData(for eventId: UUID, now: Date = Date()) throws -> Data {
        let payload = try store.read { state -> EventData in
            guard let e = state.events.first(where: { $0.id == eventId }) else { throw ExchangeError.unknownEvent }
            guard e.isOrganizer else { throw ExchangeError.notOrganizer }
            return EventData(eventId: e.id, sentAt: now, prospects: e.activeProspects)
        }
        return try Self.encoder.encode(payload)
    }

    /// Conseiller side: replaces the event's prospects with what the organizer sent. Returns how many there are.
    /// `lastSentAt` / `lastSentCount` record the reception, since a conseiller never sends anything.
    @discardableResult
    func receiveEventData(_ data: Data, now: Date = Date()) throws -> Int {
        guard let payload = try? Self.decoder.decode(EventData.self, from: data) else { throw ExchangeError.notAnEventData }
        return try store.write { state in
            guard let i = state.events.firstIndex(where: { $0.id == payload.eventId }) else { throw ExchangeError.unknownEvent }
            guard !state.events[i].isOrganizer else { throw ExchangeError.notOrganizer }
            state.events[i].prospects = payload.prospects
            state.events[i].lastSentAt = now
            state.events[i].lastSentCount = payload.prospects.count
            return payload.prospects.count
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
