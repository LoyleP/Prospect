// Local/Invitation.swift
// How an agent joins an event without any server: the organizer shows a QR code (or shares a link)
// holding the event's details and its public key. Scanning it creates the event on the agent's phone.
import Foundation

struct Invitation: Equatable, Sendable {
    struct ProgramInfo: Equatable, Sendable {
        var id: UUID
        var name: String
        var color: String
        var order: Int
    }

    var version = 1
    var eventId: UUID
    var name: String
    var date: String
    var endsAt: Date?
    var organizerName: String
    var publicKey: String
    var eventLabel: String
    var programs: [ProgramInfo]

    static let scheme = "prospect"

    init(eventId: UUID, name: String, date: String, endsAt: Date?, organizerName: String,
         publicKey: String, eventLabel: String, programs: [ProgramInfo]) {
        self.eventId = eventId; self.name = name; self.date = date; self.endsAt = endsAt
        self.organizerName = organizerName; self.publicKey = publicKey
        self.eventLabel = eventLabel; self.programs = programs
    }

    // MARK: Compact wire format
    // The QR code has to stay easy to scan, so the payload is as small as it can be: ids as 22 base64url
    // characters, programs as [id, name, color] triples whose order is their position, the end time as minutes.

    private struct Wire: Codable {
        var v: Int
        var e: String
        var n: String
        var d: String
        var t: Int?
        var o: String
        var k: String
        var l: String
        var p: [[String]]
    }

    /// `prospect://join?i=<payload>`: what the QR code contains and what the share link opens.
    var url: URL {
        let wire = Wire(
            v: version, e: Self.short(eventId), n: name, d: date,
            t: endsAt.map { Int($0.timeIntervalSince1970 / 60) }, o: organizerName, k: publicKey, l: eventLabel,
            p: programs.sorted { $0.order < $1.order }.map { [Self.short($0.id), $0.name, $0.color.replacingOccurrences(of: "#", with: "")] }
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = (try? enc.encode(wire)) ?? Data()
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "join"
        c.queryItems = [URLQueryItem(name: "i", value: Self.base64URL(json))]
        return c.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "join",
              let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "i" })?.value,
              let data = Self.data(fromBase64URL: item),
              let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.v == 1,
              let eventId = Self.uuid(fromShort: wire.e) else { return nil }
        var programs: [ProgramInfo] = []
        for (index, triple) in wire.p.enumerated() {
            guard triple.count == 3, let id = Self.uuid(fromShort: triple[0]) else { return nil }
            programs.append(.init(id: id, name: triple[1], color: "#" + triple[2], order: index))
        }
        self.init(eventId: eventId, name: wire.n, date: wire.d, endsAt: wire.t.map { Date(timeIntervalSince1970: Double($0) * 60) },
                  organizerName: wire.o, publicKey: wire.k, eventLabel: wire.l, programs: programs)
    }

    /// Accepts a scanned QR string or pasted text.
    init?(text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(url: url)
    }

    private static func short(_ id: UUID) -> String {
        base64URL(withUnsafeBytes(of: id.uuid) { Data($0) })
    }

    private static func uuid(fromShort s: String) -> UUID? {
        guard let d = data(fromBase64URL: s), d.count == 16 else { return nil }
        return d.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromBase64URL s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}
