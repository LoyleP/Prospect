// Services/EndReminder.swift
// There is no server to push a notification, so each agent's phone schedules its own: at the event's
// end time it reminds the agent to send their prospects to the organizer.
import Foundation
import UserNotifications

enum EndReminder {
    private static func id(_ event: UUID) -> String { "end-reminder-\(event.uuidString)" }

    static func schedule(for invitation: Invitation) {
        guard let endsAt = invitation.endsAt, endsAt > Date() else { return }
        schedule(eventId: invitation.eventId, name: invitation.name, organizer: invitation.organizerName, at: endsAt)
    }

    static func schedule(eventId: UUID, name: String, organizer: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L("\(name) has ended")
            content.body = L("Send your prospects to \(organizer) from the Send tab.")
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: id(eventId), content: content, trigger: trigger))
        }
    }

    static func cancel(eventId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(eventId)])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
