// Models/SessionActivityAttributes.swift
// Shared between the main app and the SessionLiveActivity widget extension.
// Add this file to BOTH targets in Xcode.
import ActivityKit
import Foundation

struct SessionActivityAttributes: ActivityAttributes {
    // Stays constant for the lifetime of the activity.
    let sessionName: String
    let sessionDate: String   // pre-formatted, e.g. "March 15, 2026"
    /// The app's language ("en" or "fr"), so the lock screen text matches the app and not only the phone.
    let language: String

    // Updated in real time as prospects are added/modified.
    struct ContentState: Codable, Hashable {
        var totalProspects: Int
        var withRdv: Int     // rdvInfo + rdvAdmission combined
        var rdvRate: Int     // 0-100 percentage
    }
}
