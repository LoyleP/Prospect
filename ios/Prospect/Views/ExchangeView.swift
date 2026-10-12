// Views/ExchangeView.swift
// Last tab. Organizer: "Collecte" (invitation, files received from agents, duplicates, end the event).
// Agent: "Envoi" (send the prospects recorded on this phone to the organizer, encrypted).
import SwiftUI
import UniformTypeIdentifiers

struct ExchangeView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ExchangeViewModel()
    @State private var showImporter = false
    @State private var showDuplicates = false
    @State private var confirmEnd = false
    @State private var shareItem: ShareItem?
    @State private var toast: Toast?

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL; let count: Int }
    private static let handoverType = UTType("com.flow.prospect.handover") ?? .data

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                heading
                if let event = vm.selected {
                    if appState.isAdmin { organizer(event) } else { agent(event) }
                } else {
                    empty
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, 120)
        }
        .background(PaperBackground())
        .scrollIndicators(.hidden)
        .toast($toast)
        .task { vm.load() }
        .onChange(of: appState.epoch) { _, _ in vm.load() }
        .onChange(of: vm.message) { _, text in
            if let text { toast = Toast(message: text, style: .success); vm.message = nil }
        }
        .onChange(of: vm.errorMessage) { _, text in
            if let text { toast = Toast(message: text, style: .error); vm.errorMessage = nil }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [Self.handoverType, .data]) { result in
            if case .success(let url) = result { vm.importFile(url) }
        }
        .sheet(isPresented: $showDuplicates) {
            DuplicatesView(groups: vm.duplicateGroups) { vm.archiveDuplicate($0) }
                .presentationBackground(Color.surfaceBackground)
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url) { completed in
                if completed {
                    vm.markSent(count: item.count)
                    toast = Toast(message: "Envoyé", style: .success)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Terminer cet événement ?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Terminer") { vm.finishEvent() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les prospects ne pourront plus être ajoutés. Rappelez à l'équipe d'envoyer les siens.")
        }
    }

    // MARK: Header

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ScreenHeading(label: appState.isAdmin ? "Collecte" : "Envoi", title: appState.isAdmin ? "Collecte" : "Envoi")
            if vm.events.count > 1, let selected = vm.selected {
                Menu {
                    ForEach(vm.events) { e in
                        Button { vm.select(e.id) } label: {
                            if e.id == selected.id { Label(e.name, systemImage: "checkmark") } else { Text(e.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selected.name).font(.textBody.weight(.medium))
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            } else if let selected = vm.selected {
                Text(selected.name).font(.textBody.weight(.medium)).foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private var empty: some View {
        EmptyStateView(
            title: appState.isAdmin ? "Aucun événement" : "Aucun événement rejoint",
            message: appState.isAdmin ? "Créez-en un dans l'onglet Prospects." : "Scannez l'invitation de l'organisateur."
        )
        .padding(.horizontal, -Space.gutter)
    }

    // MARK: Organizer

    @ViewBuilder
    private func organizer(_ event: StoredEvent) -> some View {
        if let url = vm.invitationURL {
            InvitationCard(url: url, eventName: event.name)
        }

        VStack(alignment: .leading, spacing: Space.m) {
            Text("Envois reçus\(event.receipts.isEmpty ? "" : " (\(event.receipts.count))")")
                .font(.textSub.weight(.medium)).foregroundStyle(Color.inkTertiary)
            if event.receipts.isEmpty {
                Text("Rien pour l'instant. Les agents envoient leurs prospects en fin d'événement.")
                    .font(.textSub).foregroundStyle(Color.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(event.receipts.sorted { $0.receivedAt > $1.receivedAt }.enumerated()), id: \.element.id) { index, r in
                        HStack(spacing: Space.m) {
                            Monogram(name: r.agentName, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.agentName).font(.textBody).foregroundStyle(Color.inkPrimary)
                                Text("\(r.count) prospect\(r.count > 1 ? "s" : "") · \(Self.relative(r.receivedAt))")
                                    .font(.textFootnote).foregroundStyle(Color.inkSecondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.success)
                        }
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 64)
                        if index < event.receipts.count - 1 { Rule().padding(.leading, 72) }
                    }
                }
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            }
            Button { showImporter = true } label: {
                Label("Importer un envoi", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("importHandover")
        }

        if !vm.duplicateGroups.isEmpty {
            Button { showDuplicates = true } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "person.2.slash").foregroundStyle(Color.warning)
                    Text("\(vm.duplicateGroups.count) doublon\(vm.duplicateGroups.count > 1 ? "s" : "") possible\(vm.duplicateGroups.count > 1 ? "s" : "")")
                        .font(.textBody).foregroundStyle(Color.inkPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.inkTertiary)
                }
                .padding(.horizontal, Space.l)
                .frame(minHeight: 60)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))
        }

        if event.status != .termine {
            Button("Terminer l'événement") { confirmEnd = true }
                .buttonStyle(.secondary)
        } else {
            Text("Événement terminé").font(.textSub).foregroundStyle(Color.inkTertiary)
        }
    }

    // MARK: Agent

    @ViewBuilder
    private func agent(_ event: StoredEvent) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(vm.mineCount)").font(.numeral(56)).foregroundStyle(Color.inkPrimary)
            Text("prospect\(vm.mineCount > 1 ? "s" : "") sur ce téléphone").font(.textSub).foregroundStyle(Color.inkSecondary)
            Rule().padding(.vertical, Space.s)
            if let sent = event.lastSentAt {
                Text("Dernier envoi \(Self.relative(sent)) · \(event.lastSentCount) prospect\(event.lastSentCount > 1 ? "s" : "")")
                    .font(.textFootnote).foregroundStyle(Color.inkSecondary)
                if vm.newSinceSend > 0 {
                    Text("\(vm.newSinceSend) nouveau\(vm.newSinceSend > 1 ? "x" : "") depuis")
                        .font(.textFootnote.weight(.medium)).foregroundStyle(Color.accent)
                }
            } else {
                Text("Pas encore envoyé").font(.textFootnote).foregroundStyle(Color.inkSecondary)
            }
            if let end = event.endsAt {
                Text("Fin prévue à \(Self.time(end))").font(.textFootnote).foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                if let file = vm.makeHandover() { shareItem = ShareItem(url: file.url, count: file.count) }
            } label: {
                Label("Envoyer à \(event.organizerName)", systemImage: "paperplane")
            }
            .buttonStyle(.primary)
            .disabled(vm.mineCount == 0)
            .accessibilityIdentifier("sendHandover")
            Text("Le fichier est chiffré : seul \(event.organizerName) peut le lire.")
                .font(.textFootnote).foregroundStyle(Color.inkTertiary)
        }
    }

    // MARK: Formatting

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
