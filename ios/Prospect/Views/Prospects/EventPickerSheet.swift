// Views/Prospects/EventPickerSheet.swift
// Switch between events. Each event is a ticket: a date stub, a perforation, the details.
// Admins get a menu per event.
import SwiftUI

struct EventPickerSheet: View {
    let summaries: [SessionSummary]
    let selectedId: UUID?
    let isAdmin: Bool
    let eventLabel: String

    var onSelect: (SessionSummary) -> Void
    var onCreate: () -> Void
    var onEdit: (SessionSummary) -> Void
    var onAccess: (SessionSummary) -> Void
    var onObjectives: (SessionSummary) -> Void
    var onToggleArchive: (SessionSummary) -> Void
    var onDelete: (SessionSummary) -> Void

    @Environment(\.dismiss) private var dismiss

    private var groups: [(title: String, items: [SessionSummary])] {
        let active = summaries.filter { !$0.isArchived }
        return [
            (L("Live"), active.filter { $0.statutSession == .enCours }),
            (L("Upcoming"), active.filter { $0.statutSession == .pasCommence }),
            (L("Finished"), active.filter { $0.statutSession == .termine }),
            (L("Archived"), summaries.filter { $0.isArchived }),
        ].filter { !$0.1.isEmpty }
    }

    private static let shortDate = PerLanguage<DateFormatter> { language in
        let f = DateFormatter(); f.locale = language.locale; f.dateFormat = language == .fr ? "d MMM" : "MMM d"; return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(L("Sessions"))
                    .font(.displayS)
                    .foregroundStyle(Color.inkPrimary)

                if isAdmin {
                    Button { dismiss(); onCreate() } label: {
                        HStack(spacing: Space.m) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.onAccent)
                                .frame(width: 30, height: 30)
                                .background(Color.accent, in: Circle())
                            Text(L("Create a session"))
                                .font(.textBody.weight(.medium))
                                .foregroundStyle(Color.inkPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 55)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .accessibilityIdentifier("createEvent")
                }

                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(group.title)
                            .font(.textSub.weight(.medium))
                            .foregroundStyle(Color.inkTertiary)
                        ForEach(group.items) { summary in
                            row(summary)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ summary: SessionSummary) -> some View {
        let selected = summary.id == selectedId
        let date = summary.session.displayDate.map { Self.shortDate.value.string(from: $0).replacingOccurrences(of: ".", with: "") }
        let count = L("\(summary.prospectCount) prospects")
        return HStack(spacing: Space.s) {
            Button {
                Haptics.selection()
                onSelect(summary)
                dismiss()
            } label: {
                HStack(spacing: Space.m) {
                    if summary.statutSession == .enCours { LiveDot() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.name)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.inkPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text([date, count].compactMap { $0 }.joined(separator: " · "))
                            .font(.textFootnote)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer(minLength: Space.s)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                }
                .frame(minHeight: 55)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdmin {
                Menu {
                    Button { dismiss(); onAccess(summary) } label: { Label(L("Invite"), systemImage: "qrcode") }
                    Button { dismiss(); onObjectives(summary) } label: { Label(L("Targets"), systemImage: "target") }
                    Button { dismiss(); onEdit(summary) } label: { Label(L("Edit"), systemImage: "pencil") }
                    Button { onToggleArchive(summary) } label: {
                        Label(summary.isArchived ? L("Unarchive") : L("Archive"), systemImage: summary.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) { dismiss(); onDelete(summary) } label: { Label(L("Delete"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkTertiary)
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Actions for \(summary.name)"))
            }
        }
        .opacity(summary.isArchived ? 0.5 : 1)
    }
}

/// The tear-off end of a ticket: month over day.
struct DateStub: View {
    let session: Session
    var live = false

    private static let month = PerLanguage<DateFormatter> { language in
        let f = DateFormatter(); f.locale = language.locale; f.dateFormat = "MMM"; return f
    }
    private static let day = PerLanguage<DateFormatter> { language in
        let f = DateFormatter(); f.locale = language.locale; f.dateFormat = "d"; return f
    }

    var body: some View {
        let date = session.displayDate
        VStack(spacing: 0) {
            Text(date.map { Self.month.value.string(from: $0).replacingOccurrences(of: ".", with: "").uppercased() } ?? "—")
                .font(.figure(11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(live ? Color.accent : Color.inkTertiary)
            Text(date.map { Self.day.value.string(from: $0) } ?? "")
                .font(.numeral(30))
                .foregroundStyle(Color.inkPrimary)
        }
        .frame(width: 66)
        .padding(.vertical, Space.m)
        .accessibilityHidden(true)
    }
}
