// Local/LocalStore.swift
// The whole app state, as one JSON file in Application Support, readable only while the phone is
// unlocked (complete file protection). Every change is written atomically.
import Foundation

final class LocalStore: @unchecked Sendable {
    static let shared = LocalStore(url: LocalStore.defaultURL)

    static var defaultURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("prospect-store.json")
    }

    private let lock = NSLock()
    private var state: LocalState
    private let url: URL?

    /// `url == nil` keeps everything in memory (tests, demo data).
    init(url: URL?, initial: LocalState? = nil) {
        self.url = url
        if let initial {
            state = initial
        } else if let url, let data = try? Data(contentsOf: url), let saved = try? Self.decoder.decode(LocalState.self, from: data) {
            state = saved
        } else {
            state = LocalState()
        }
    }

    func read<T>(_ body: (LocalState) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(state)
    }

    @discardableResult
    func write<T>(_ body: (inout LocalState) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        let result = try body(&state)
        save()
        return result
    }

    /// Forgets everything on this phone.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        state = LocalState()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func save() {
        guard let url, let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
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
