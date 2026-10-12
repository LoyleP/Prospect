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
            ("En direct", active.filter { $0.statutSession == .enCours }),
            ("À venir", active.filter { $0.statutSession == .pasCommence }),
            ("Terminés", active.filter { $0.statutSession == .termine }),
            ("Archivés", summaries.filter { $0.isArchived }),
        ].filter { !$0.1.isEmpty }
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM"; return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(eventLabel)
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
                            Text("Créer : \(eventLabel)")
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
        let date = summary.session.displayDate.map { Self.shortDate.string(from: $0).replacingOccurrences(of: ".", with: "") }
        let count = "\(summary.prospectCount) prospect\(summary.prospectCount > 1 ? "s" : "")"
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
                    Button { dismiss(); onAccess(summary) } label: { Label("Inviter", systemImage: "qrcode") }
                    Button { dismiss(); onObjectives(summary) } label: { Label("Objectifs", systemImage: "target") }
                    Button { dismiss(); onEdit(summary) } label: { Label("Modifier", systemImage: "pencil") }
                    Button { onToggleArchive(summary) } label: {
                        Label(summary.isArchived ? "Désarchiver" : "Archiver", systemImage: summary.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) { dismiss(); onDelete(summary) } label: { Label("Supprimer", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkTertiary)
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions pour \(summary.name)")
            }
        }
        .opacity(summary.isArchived ? 0.5 : 1)
    }
}

/// The tear-off end of a ticket: month over day.
struct DateStub: View {
    let session: Session
    var live = false

    private static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "MMM"; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d"; return f
    }()

    var body: some View {
        let date = session.displayDate
        VStack(spacing: 0) {
            Text(date.map { Self.month.string(from: $0).replacingOccurrences(of: ".", with: "").uppercased() } ?? "—")
                .font(.figure(11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(live ? Color.accent : Color.inkTertiary)
            Text(date.map { Self.day.string(from: $0) } ?? "")
                .font(.numeral(30))
                .foregroundStyle(Color.inkPrimary)
        }
        .frame(width: 66)
        .padding(.vertical, Space.m)
        .accessibilityHidden(true)
    }
}
