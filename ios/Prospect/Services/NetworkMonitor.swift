// Services/NetworkMonitor.swift
// Whether the phone currently has a network path. Drives the "hors connexion" banner and
// triggers the upload of prospects saved while offline.
import Foundation
import Network
import Observation

@Observable @MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }
}
