// Services/LiveActivityManager.swift
// Manages the single Live Activity for an in-progress event.
import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<SessionActivityAttributes>?

    // MARK: - Lifecycle

    func start(session: Session, prospects: [Prospect]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Reattach to an existing activity for this session if one is already running.
        if let existing = Activity<SessionActivityAttributes>.activities.first(where: {
            $0.attributes.sessionName == session.name
        }) {
            currentActivity = existing
            Task { await update(prospects: prospects) }
            return
        }

        // End any stale activities from previous sessions.
        Task { await endAll() }

        let attributes = SessionActivityAttributes(
            sessionName: session.name,
            sessionDate: session.formattedDate,
            language: Language.current.rawValue
        )
        let content = ActivityContent(state: makeState(from: prospects), staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("[LiveActivity] Failed to start: \(error.localizedDescription)")
        }
    }

    func update(prospects: [Prospect]) async {
        guard let activity = currentActivity else { return }
        let content = ActivityContent(state: makeState(from: prospects), staleDate: nil)
        await activity.update(content)
    }

    func end() {
        Task { await endAll() }
        currentActivity = nil
    }

    // MARK: - Test

    func startTest() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task { await endAll() }
        let attributes = SessionActivityAttributes(
            sessionName: L("Test event"),
            sessionDate: Date().formatted(.dateTime.day().month(.wide).year().locale(Language.current.locale)),
            language: Language.current.rawValue
        )
        let state = SessionActivityAttributes.ContentState(
            totalProspects: 28,
            withRdv: 19,
            rdvRate: 67
        )
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] Test start failed: \(error.localizedDescription)")
        }
    }

    var isRunning: Bool {
        currentActivity != nil || !Activity<SessionActivityAttributes>.activities.isEmpty
    }

    // MARK: - Helpers

    private func endAll() async {
        for activity in Activity<SessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .default)
        }
    }

    private func makeState(from prospects: [Prospect]) -> SessionActivityAttributes.ContentState {
        let rdvStatuts: Set<String> = [Statut.rdvInfo.rawValue, Statut.rdvAdmission.rawValue]
        let withRdv = prospects.filter { rdvStatuts.contains($0.statut) }.count
        let rate = prospects.isEmpty ? 0 : Int((Double(withRdv) / Double(prospects.count)) * 100)
        return SessionActivityAttributes.ContentState(
            totalProspects: prospects.count,
            withRdv: withRdv,
            rdvRate: rate
        )
    }
}
