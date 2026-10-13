// LiveActivity/EventLiveActivityWidget.swift
// Shares Models/SessionActivityAttributes.swift with the app (see ios/project.yml).
import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget declaration

struct EventLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(context.state.totalProspects)")
                            .font(.title.bold())
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text("prospects")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                    .environment(\.locale, context.attributes.locale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.rdvRate)%")
                            .font(.title.bold())
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                        Text("Meeting rate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                    .environment(\.locale, context.attributes.locale)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.sessionName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RdvProgressBar(rate: context.state.rdvRate)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(context.state.totalProspects)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.primary)
            } compactTrailing: {
                Text("\(context.state.rdvRate)%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.blue)
            } minimal: {
                Text("\(context.state.rdvRate)%")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Lock Screen view

private struct SessionLockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.sessionName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(context.attributes.sessionDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
            }

            // Stats row
            HStack(spacing: 0) {
                StatCell(value: "\(context.state.totalProspects)", label: "prospects")
                Divider().frame(height: 32)
                StatCell(value: "\(context.state.withRdv)", label: "With meeting")
                Divider().frame(height: 32)
                StatCell(value: "\(context.state.rdvRate)%", label: "Meeting rate", accent: .blue)
            }

            // Progress bar
            RdvProgressBar(rate: context.state.rdvRate)
        }
        .padding(16)
        .environment(\.locale, context.attributes.locale)
    }
}

extension SessionActivityAttributes {
    /// The app's language, applied to the extension's text.
    var locale: Locale { Locale(identifier: language == "fr" ? "fr_FR" : "en_US") }
}

// MARK: - Shared sub-views

private struct StatCell: View {
    let value: String
    let label: LocalizedStringKey
    var accent: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RdvProgressBar: View {
    let rate: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                    .frame(height: 6)
                Capsule()
                    .fill(.blue)
                    .frame(width: geo.size.width * CGFloat(rate) / 100, height: 6)
            }
        }
        .frame(height: 6)
    }
}

