// LiveActivity/LiveActivityBundle.swift
// Widget extension entry point: the Lock Screen / Dynamic Island activity for an event in progress.
import WidgetKit
import SwiftUI

@main
struct ProspectLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        EventLiveActivityWidget()
    }
}
