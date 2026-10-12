// Local/NearbyTransfer.swift
// Phone-to-phone transfer with no server: Multipeer Connectivity (Bluetooth / peer-to-peer Wi-Fi), sessions that
// require encryption. The agent's file is *also* encrypted to the organizer (see Handover), so even a stranger
// posing as the organizer could not read it.
//
//   agent / conseiller  ── NearbyClient ──▶  NearbyHost  (organizer, "Recevoir" switched on)
//
// Agents send their handover file and get an acknowledgement. A conseiller asks for the event's data: the organizer
// has to approve each request by hand, because the invitation QR code is not a secret.
import Foundation
import MultipeerConnectivity
import Observation
import UIKit

enum Nearby {
    static let serviceType = "prospect-sync"

    /// First byte of every message.
    enum Kind: UInt8 {
        case handover = 1       // agent → organizer: the encrypted file
        case handoverAck = 2    // organizer → agent: Ack
        case eventData = 3      // organizer → conseiller: EventExchange.EventData
        case eventAck = 4       // conseiller → organizer
    }

    /// Sent as the invitation context: who is asking, and for what ("a" = agent sending, "c" = conseiller receiving).
    struct Hello: Codable, Equatable {
        var role: String
        var name: String
    }

    struct Ack: Codable, Equatable {
        var ok: Bool
        var added = 0
        var updated = 0
        var error: String?
    }

    static func frame(_ kind: Kind, _ payload: Data = Data()) -> Data { Data([kind.rawValue]) + payload }

    static func unframe(_ data: Data) -> (Kind, Data)? {
        guard let first = data.first, let kind = Kind(rawValue: first) else { return nil }
        return (kind, Data(data.dropFirst()))
    }

    static func peerID(_ name: String) -> MCPeerID {
        // MCPeerID traps on more than 63 *bytes*, which a long accented name easily exceeds.
        var trimmed = ""
        for character in name.trimmingCharacters(in: .whitespaces) {
            guard trimmed.utf8.count + String(character).utf8.count <= 60 else { break }
            trimmed.append(character)
        }
        return MCPeerID(displayName: trimmed.isEmpty ? "Prospect" : trimmed)
    }

    static func makeSession(_ peer: MCPeerID) -> MCSession {
        MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
    }
}

// MARK: - Organizer

/// Advertises one event. Agents are accepted automatically (their file only opens with the organizer's key);
/// conseillers wait in `requests` until the organizer taps Send.
@Observable
@MainActor
final class NearbyHost: NSObject {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let name: String
        fileprivate let peer: MCPeerID
    }

    private(set) var isRunning = false
    private(set) var requests: [Request] = []

    /// A file arrived from an agent: import it and say what happened.
    @ObservationIgnored var onHandover: ((Data) -> Nearby.Ack)?
    /// The event's data for an approved conseiller.
    @ObservationIgnored var eventData: (() -> Data?)?
    /// Something worth telling the organizer.
    @ObservationIgnored var onNotice: ((String) -> Void)?

    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var handlers: [UUID: (Bool, MCSession?) -> Void] = [:]
    @ObservationIgnored private var approved: [MCPeerID: String] = [:]

    func start(eventId: UUID, displayName: String) {
        stop()
        let peer = Nearby.peerID(displayName)
        let session = Nearby.makeSession(peer)
        session.delegate = self
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["e": Invitation.short(eventId)],
                                                   serviceType: Nearby.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.session = session
        self.advertiser = advertiser
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        handlers.values.forEach { $0(false, nil) }
        handlers.removeAll()
        approved.removeAll()
        requests.removeAll()
        advertiser = nil
        session = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func approve(_ request: Request) {
        guard let handler = handlers.removeValue(forKey: request.id) else { return }
        approved[request.peer] = request.name
        requests.removeAll { $0.id == request.id }
        handler(true, session)
    }

    func decline(_ request: Request) {
        handlers.removeValue(forKey: request.id)?(false, nil)
        requests.removeAll { $0.id == request.id }
    }

    // MARK: Events from the delegates (already on the main actor)

    fileprivate func received(invitationFrom peer: MCPeerID, hello: Nearby.Hello?, handler: @escaping (Bool, MCSession?) -> Void) {
        guard session != nil else { handler(false, nil); return }
        if hello?.role == "c" {
            let request = Request(name: hello?.name ?? peer.displayName, peer: peer)
            handlers[request.id] = handler
            requests.append(request)
            Haptics.tap()
        } else {
            handler(true, session)
        }
    }

    fileprivate func received(_ data: Data, from peer: MCPeerID) {
        guard let (kind, payload) = Nearby.unframe(data) else { return }
        switch kind {
        case .handover:
            let ack = onHandover?(payload) ?? Nearby.Ack(ok: false, error: "Réception indisponible.")
            send(.handoverAck, (try? JSONEncoder().encode(ack)) ?? Data(), to: peer)
        case .eventAck:
            onNotice?("Données envoyées à \(peer.displayName)")
        default:
            break
        }
    }

    fileprivate func connected(_ peer: MCPeerID) {
        guard approved.removeValue(forKey: peer) != nil, let data = eventData?() else { return }
        send(.eventData, data, to: peer)
    }

    private func send(_ kind: Nearby.Kind, _ payload: Data, to peer: MCPeerID) {
        try? session?.send(Nearby.frame(kind, payload), toPeers: [peer], with: .reliable)
    }
}

extension NearbyHost: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let hello = context.flatMap { try? JSONDecoder().decode(Nearby.Hello.self, from: $0) }
        Task { @MainActor in self.received(invitationFrom: peerID, hello: hello, handler: invitationHandler) }
    }
}

extension NearbyHost: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected { Task { @MainActor in self.connected(peerID) } }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.received(data, from: peerID) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             at localURL: URL?, withError error: Error?) {}
}

// MARK: - Agent or conseiller

/// Looks for the organizer of one event, then either sends a file (agent) or asks for the event's data (conseiller).
@Observable
@MainActor
final class NearbyClient: NSObject {
    enum State: Equatable {
        case idle
        case searching                // looking for the organizer's phone
        case waiting                  // found; the organizer has to accept (conseiller)
        case sending
        case done(Nearby.Ack?)
        case failed(String)
    }

    private(set) var state: State = .idle
    var isBusy: Bool {
        switch state {
        case .searching, .waiting, .sending: return true
        default: return false
        }
    }

    /// Conseiller side: the event's data arrived. Return false if it could not be stored.
    @ObservationIgnored var onEventData: ((Data) -> Bool)?

    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var eventKey = ""
    @ObservationIgnored private var hello = Nearby.Hello(role: "a", name: "")
    @ObservationIgnored private var outgoing: Data?
    @ObservationIgnored private var invited = false

    /// Agent: send the encrypted file and wait for the organizer's acknowledgement.
    func sendHandover(_ file: Data, eventId: UUID, name: String) {
        begin(eventId: eventId, hello: .init(role: "a", name: name), outgoing: file)
    }

    /// Conseiller: ask the organizer for the event's data.
    func requestEventData(eventId: UUID, name: String) {
        begin(eventId: eventId, hello: .init(role: "c", name: name), outgoing: nil)
    }

    func cancel() {
        finish(.idle)
    }

    private func begin(eventId: UUID, hello: Nearby.Hello, outgoing: Data?) {
        finish(.idle)
        self.hello = hello
        self.outgoing = outgoing
        eventKey = Invitation.short(eventId)
        invited = false

        let peer = Nearby.peerID(hello.name)
        let session = Nearby.makeSession(peer)
        session.delegate = self
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Nearby.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.session = session
        self.browser = browser
        state = .searching

        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled, self.state == .searching else { return }
            self.finish(.failed("Organisateur introuvable. Il doit ouvrir Recevoir."))
        }
    }

    private func finish(_ final: State) {
        timeout?.cancel()
        timeout = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        let old = session
        session = nil
        outgoing = nil
        state = final
        // Let a last acknowledgement leave before the link goes down.
        if let old { Task { try? await Task.sleep(for: .seconds(1)); old.disconnect() } }
    }

    // MARK: Events from the delegates (already on the main actor)

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard !invited, info?["e"] == eventKey, let session, let browser else { return }
        invited = true
        let context = try? JSONEncoder().encode(hello)
        state = hello.role == "c" ? .waiting : .searching
        timeout?.cancel()
        browser.invitePeer(peer, to: session, withContext: context, timeout: 120)
    }

    fileprivate func changed(_ peer: MCPeerID, to peerState: MCSessionState) {
        switch peerState {
        case .connected:
            if let outgoing {
                state = .sending
                // A transfer that stalls must fail visibly rather than spin forever.
                timeout?.cancel()
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(90))
                    guard let self, !Task.isCancelled, self.state == .sending else { return }
                    self.finish(.failed("L'envoi a pris trop de temps."))
                }
                do {
                    try session?.send(Nearby.frame(.handover, outgoing), toPeers: [peer], with: .reliable)
                } catch {
                    finish(.failed("Envoi impossible."))
                }
            } else {
                state = .waiting
            }
        case .notConnected:
            if invited, isBusy { finish(.failed(hello.role == "c" ? "L'organisateur n'a pas accepté." : "Connexion perdue.")) }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    fileprivate func received(_ data: Data, from peer: MCPeerID) {
        guard let (kind, payload) = Nearby.unframe(data) else { return }
        switch kind {
        case .handoverAck:
            let ack = try? JSONDecoder().decode(Nearby.Ack.self, from: payload)
            if ack?.ok == true { finish(.done(ack)) } else { finish(.failed(ack?.error ?? "Fichier refusé.")) }
        case .eventData:
            if onEventData?(payload) == true {
                try? session?.send(Nearby.frame(.eventAck), toPeers: [peer], with: .reliable)
                finish(.done(nil))
            } else {
                finish(.failed("Données illisibles."))
            }
        default:
            break
        }
    }
}

extension NearbyClient: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in self.found(peerID, info: info) }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.finish(.failed("Recherche impossible : autorisez le réseau local dans Réglages.")) }
    }
}

extension NearbyClient: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.changed(peerID, to: state) }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.received(data, from: peerID) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             at localURL: URL?, withError error: Error?) {}
}
