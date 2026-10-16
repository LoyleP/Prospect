// Views/ExchangeView.swift
// Last tab. Organizer: "Collecte" (invitation, receive from nearby phones, duplicates, end the event).
// Agent: "Envoi" (send the prospects recorded on this phone to the organizer's phone, nearby, encrypted).
// Conseiller: "Réception" (ask the organizer's phone for the event's data).
import SwiftUI
import UniformTypeIdentifiers

struct ExchangeView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ExchangeViewModel()
    @State private var showImporter = false
    @State private var showDuplicates = false
    @State private var confirmEnd = false
    @State private var toast: Toast?

    private static let handoverType = UTType("com.flow.prospect.handover") ?? .data

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                if let event = vm.selected {
                    if appState.isAdmin { organizer(event) } else if appState.isConseiller { conseiller(event) } else { agent(event) }
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
        // Every tab stays alive, so prospects added elsewhere would never reach this count: reload when it is opened.
        .onChange(of: appState.selectedTab) { _, tab in if tab == .exchange { vm.load() } }
        .onChange(of: vm.message) { _, text in
            if let text { Haptics.success(); toast = Toast(message: text, style: .success); vm.message = nil }
        }
        .onChange(of: vm.errorMessage) { _, text in
            if let text { toast = Toast(message: text, style: .error); vm.errorMessage = nil }
        }
        .onChange(of: vm.client.state) { _, state in vm.clientStateChanged(state) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [Self.handoverType, .data]) { result in
            if case .success(let url) = result { vm.importFile(url) }
        }
        .sheet(isPresented: $showDuplicates) {
            DuplicatesView(groups: vm.duplicateGroups) { vm.archiveDuplicate($0) }
                .presentationBackground(Color.surfaceBackground)
        }
        .confirmationDialog(L("End this session?"), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(L("End")) { vm.finishEvent() }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    // MARK: Header

    private var heading: String { appState.isAdmin ? L("Collect") : (appState.isConseiller ? L("Inbox") : L("Send")) }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ScreenHeading(label: heading, title: heading)
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
            title: appState.isAdmin ? L("No sessions") : L("No session joined"),
            message: appState.isAdmin ? L("Create one in the Prospects tab.") : L("Scan the organizer's invitation.")
        )
        .padding(.horizontal, -Space.gutter)
    }

    // MARK: Organizer

    @ViewBuilder
    private func organizer(_ event: StoredEvent) -> some View {
        if let url = vm.invitationURL {
            InvitationCard(url: url, eventName: event.name)
        }

        receiving

        VStack(alignment: .leading, spacing: Space.m) {
            if !event.receipts.isEmpty {
                Text(L("Received (\(event.receipts.count))"))
                    .font(.textSub.weight(.medium)).foregroundStyle(Color.inkTertiary)

                VStack(spacing: 0) {
                    ForEach(Array(event.receipts.sorted { $0.receivedAt > $1.receivedAt }.enumerated()), id: \.element.id) { index, r in
                        let receivedCount = L("\(r.count) prospects")
                        HStack(spacing: Space.m) {
                            Monogram(name: r.agentName, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.agentName).font(.textBody).foregroundStyle(Color.inkPrimary)
                                Text("\(receivedCount) · \(Self.relative(r.receivedAt))")
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
                Label(L("Import a file"), systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("importHandover")

            Button {
                event.importsComplete ? Haptics.tap() : Haptics.success()
                withAnimation(.curve(Motion.standard)) { vm.toggleImportsComplete() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: event.importsComplete ? "checkmark.circle.fill" : "circle")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: event.importsComplete)
                    Text(L("Imports complete"))
                }
                .foregroundStyle(event.importsComplete ? Color.success : Color.inkPrimary)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("importsComplete")
        }

        if !vm.duplicateGroups.isEmpty {
            Button { showDuplicates = true } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "person.2.slash").foregroundStyle(Color.warning)
                    Text(L("\(vm.duplicateGroups.count) possible duplicates"))
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
            Button(L("End the session")) { confirmEnd = true }
                .buttonStyle(.secondary)
        } else {
            Text(L("Session finished")).font(.textSub).foregroundStyle(Color.inkTertiary)
        }
    }

    // MARK: Agent

    @ViewBuilder
    private func agent(_ event: StoredEvent) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(vm.mineCount)").font(.numeral(56)).foregroundStyle(Color.inkPrimary)
                    .contentTransition(.numericText())
                    .animation(.curve(Motion.standard), value: vm.mineCount)
                if vm.newSinceSend > 0 && event.lastSentAt != nil {
                    Text("+\(vm.newSinceSend)").font(.textHeadline).foregroundStyle(Color.accent)
                }
            }
            Text(prospectsNoun(vm.mineCount)).font(.textSub).foregroundStyle(Color.inkSecondary)
            if let sent = event.lastSentAt {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                    Text(Self.relative(sent)).foregroundStyle(Color.inkSecondary)
                }
                .font(.textFootnote)
                .padding(.top, Space.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

        VStack(alignment: .leading, spacing: Space.s) {
            Button { vm.sendNearby() } label: {
                if vm.client.isBusy {
                    HStack(spacing: Space.s) { ProgressView().tint(Color.onAccent); Text(busyText) }
                } else {
                    Label(event.organizerName, systemImage: "paperplane")
                }
            }
            .buttonStyle(.primary)
            .disabled(vm.mineCount == 0 || vm.client.isBusy)
            .accessibilityIdentifier("sendHandover")
        }
    }

    // MARK: Conseiller

    @ViewBuilder
    private func conseiller(_ event: StoredEvent) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(event.activeProspects.count)").font(.numeral(56)).foregroundStyle(Color.inkPrimary)
                .contentTransition(.numericText())
                .animation(.curve(Motion.standard), value: event.activeProspects.count)
            Text(prospectsNoun(event.activeProspects.count)).font(.textSub).foregroundStyle(Color.inkSecondary)
            if let received = event.lastSentAt {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                    Text(Self.relative(received)).foregroundStyle(Color.inkSecondary)
                }
                .font(.textFootnote)
                .padding(.top, Space.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

        Button { vm.receiveNearby() } label: {
            if vm.client.isBusy {
                HStack(spacing: Space.s) { ProgressView().tint(Color.onAccent); Text(busyText) }
            } else {
                Label(event.organizerName, systemImage: "arrow.down.circle")
            }
        }
        .buttonStyle(.primary)
        .disabled(vm.client.isBusy)
        .accessibilityIdentifier("receiveEventData")
    }

    private var busyText: String {
        switch vm.client.state {
        case .waiting: return appState.isConseiller ? L("Waiting for the organizer") : L("Connecting…")
        case .sending: return L("Sending…")
        default: return L("Searching…")
        }
    }

    // MARK: Organizer: receiving

    @ViewBuilder
    private var receiving: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if vm.host.isRunning {
                HStack(spacing: Space.m) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text(L("Listening")).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                    Spacer()
                    Button(L("Stop")) { Haptics.tap(); vm.stopReceiving() }
                        .font(.textBody.weight(.medium))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minWidth: 55, minHeight: 55)
                        .accessibilityIdentifier("stopReceiving")
                }
                .padding(.leading, Space.l)
                .padding(.trailing, Space.s)
                .frame(minHeight: 64)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

                ForEach(vm.host.requests) { request in
                    HStack(spacing: Space.m) {
                        Monogram(name: request.name, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(request.name).font(.textBody).foregroundStyle(Color.inkPrimary)
                            Text(L("Advisor")).font(.textFootnote).foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Button { Haptics.success(); vm.host.decline(request) } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.inkSecondary)
                                .frame(width: 44, height: 44)
                                .background(Color.surfaceCard2, in: Circle())
                        }
                        .accessibilityLabel(L("Decline"))
                        Button { Haptics.success(); vm.host.approve(request) } label: {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.onAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.accent, in: Circle())
                        }
                        .accessibilityLabel(L("Send the data"))
                        .accessibilityIdentifier("approveConseiller")
                    }
                    .padding(.horizontal, Space.l)
                    .frame(minHeight: 64)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    .transition(.rise)
                }
            } else {
                Button { vm.startReceiving() } label: {
                    Label(L("Receive"), systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("startReceiving")
            }
        }
        .animation(.curve(Motion.standard), value: vm.host.isRunning)
        .animation(.curve(Motion.standard), value: vm.host.requests)
    }

    // MARK: Formatting

    private static func relative(_ date: Date) -> String {
        // A file that just arrived is stamped a hair after "now": don't print "dans 0 s".
        if abs(date.timeIntervalSinceNow) < 10 { return L("just now") }
        let f = RelativeDateTimeFormatter()
        f.locale = Language.current.locale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Language.current.locale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
