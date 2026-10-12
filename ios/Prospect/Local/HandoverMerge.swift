// Local/HandoverMerge.swift
// The organizer's side of a handover: fold an agent's prospects into the event without duplicating
// anything, and spot visitors who were probably recorded twice by different agents.
import Foundation

struct MergeResult: Equatable, Sendable {
    var added = 0
    var updated = 0
    var unchanged = 0
}

enum HandoverMerge {
    /// Same prospect id → keep the most recently edited copy. New ids are added. Importing the same
    /// file twice therefore changes nothing.
    @discardableResult
    static func merge(_ payload: Handover.Payload, into event: inout StoredEvent, now: Date = Date()) -> MergeResult {
        var result = MergeResult()
        for incoming in payload.prospects {
            var p = incoming
            if p.agentNom.isEmpty { p.agentNom = payload.agentName }
            if let i = event.prospects.firstIndex(where: { $0.id == p.id }) {
                let existing = ISODates.parse(event.prospects[i].updatedAt) ?? .distantPast
                let candidate = ISODates.parse(p.updatedAt) ?? .distantPast
                if candidate > existing || (event.prospects[i].deletedAt != nil && p.deletedAt == nil && candidate >= existing) {
                    event.prospects[i] = p
                    result.updated += 1
                } else {
                    result.unchanged += 1
                }
            } else {
                event.prospects.append(p)
                result.added += 1
            }
        }
        let receipt = HandoverReceipt(id: payload.agentId, agentName: payload.agentName, count: payload.prospects.count,
                                      added: result.added, receivedAt: now)
        if let i = event.receipts.firstIndex(where: { $0.id == payload.agentId }) {
            event.receipts[i] = receipt
        } else {
            event.receipts.append(receipt)
        }
        return result
    }

    /// Groups of active prospects that share an email or a phone number.
    static func duplicateGroups(in prospects: [Prospect]) -> [[Prospect]] {
        let active = prospects.filter { $0.deletedAt == nil }
        var parent = Array(0..<active.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        var byKey: [String: Int] = [:]
        for (i, p) in active.enumerated() {
            for key in keys(for: p) {
                if let j = byKey[key] { union(i, j) } else { byKey[key] = i }
            }
        }
        var groups: [Int: [Prospect]] = [:]
        for (i, p) in active.enumerated() { groups[find(i), default: []].append(p) }
        return groups.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.createdAt < $1.createdAt } }
            .sorted { ($0.first?.createdAt ?? "") < ($1.first?.createdAt ?? "") }
    }

    private static func keys(for p: Prospect) -> [String] {
        var keys: [String] = []
        let email = p.email.trimmingCharacters(in: .whitespaces).lowercased()
        if !email.isEmpty { keys.append("e:" + email) }
        let digits = p.telephone.filter(\.isNumber)
        if digits.count >= 6 { keys.append("p:" + digits.suffix(9)) }
        return keys
    }
}
