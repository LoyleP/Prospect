// Views/SessionCreationFlow.swift
// Creating a session, in three pages that look and behave the same: 1. name and date, 2. programs, 3. targets.
// Used by the first launch (which also asks for the organizer's name) and by "Create a session" inside the app.
import SwiftUI

/// Everything an organizer sets while creating a session.
struct SessionDraft {
    var organizerName = ""
    var name = ""
    var date = Date()
    var endReminder = false
    var endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    var preRegistered = 0
    var rdvTargetLow = 0
    var rdvTargetHigh = 0
    var programObjectives: [UUID: Int] = [:]

    var cleanName: String { name.trimmingCharacters(in: .whitespaces) }
    var cleanOrganizer: String { organizerName.trimmingCharacters(in: .whitespaces) }

    /// The end of the session: its day with the picked hour and minute.
    var endsAt: Date? {
        guard endReminder else { return nil }
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: endTime)
        return cal.date(bySettingHour: t.hour ?? 17, minute: t.minute ?? 0, second: 0, of: date) ?? date
    }

    /// What is saved on the session once it exists (its name and date are given when it is created).
    var patch: SessionPatch {
        SessionPatch(
            preRegistered: preRegistered,
            rdvTargetLow: rdvTargetLow,
            rdvTargetHigh: max(rdvTargetHigh, rdvTargetLow),
            programObjectives: Dictionary(uniqueKeysWithValues: programObjectives.filter { $0.value > 0 }.map { ($0.key.uuidString.lowercased(), $0.value) }),
            endsAt: endsAt
        )
    }
}

struct SessionCreationFlow: View {
    /// 0 name and date, 1 programs, 2 targets. The host owns it so its back button can step back.
    @Binding var page: Int
    /// First launch: the organizer's own name is asked on the first page too.
    var askOrganizerName = false
    let onCreate: (SessionDraft) async throws -> Void

    @Environment(AppState.self) private var appState
    @State private var draft = SessionDraft()
    @State private var isCreating = false
    @State private var errorText: String?
    @State private var forward = true
    @FocusState private var focused: Field?
    private enum Field { case organizer, session }

    static let pageCount = 3

    private var slide: AnyTransition {
        forward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    private var canContinue: Bool {
        guard !isCreating else { return false }
        if page == 0 { return !draft.cleanName.isEmpty && (!askOrganizerName || !draft.cleanOrganizer.isEmpty) }
        return true
    }

    private var title: String {
        switch page {
        case 0: return L("Create a session")
        case 1: return L("Programs")
        default: return L("Targets")
        }
    }

    private var subtitle: String? {
        switch page {
        case 1: return L("What visitors can be interested in. They stay on this phone for your next sessions.")
        case 2: return L("Optional. You can change them later.")
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        progress
                        Text(title).font(.displayL).foregroundStyle(Color.inkPrimary)
                        if let subtitle { Text(subtitle).font(.textBody).foregroundStyle(Color.inkSecondary) }
                    }
                    ZStack(alignment: .top) {
                        switch page {
                        case 0: basics.transition(slide)
                        case 1: programs.transition(slide)
                        default: targets.transition(slide)
                        }
                    }
                }
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            if let errorText { InlineError(text: errorText).transition(.drop) }
            Button(action: advance) {
                ZStack {
                    Text(page == Self.pageCount - 1 ? L("Create") : L("Continue")).opacity(isCreating ? 0 : 1)
                    if isCreating { ProgressView().tint(Color.onAccent) }
                }
            }
            .buttonStyle(.primary)
            .disabled(!canContinue)
            .accessibilityIdentifier("continueOrganize")
            .padding(.bottom, Space.s)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.curve(Motion.standard), value: page)
        .animation(.curve(Motion.micro), value: errorText)
        .onChange(of: page) { old, new in forward = new > old; focused = nil }
        .task {
            // Bring the keyboard up after the screen has slid in.
            try? await Task.sleep(for: .milliseconds(Int(Motion.standard * 1000)))
            if page == 0 { focused = askOrganizerName ? .organizer : .session }
        }
    }

    // MARK: Pages

    /// "1 of 3" as three bars: the same on every page.
    private var progress: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? Color.accent : Color.ruleStrong.opacity(0.5))
                    .frame(height: 4)
            }
        }
        .padding(.bottom, Space.s)
        .accessibilityElement()
        .accessibilityLabel(L("Step \(page + 1) of \(Self.pageCount)"))
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if askOrganizerName {
                LabeledField(title: L("Your name"), isFocused: focused == .organizer) {
                    TextField("", text: $draft.organizerName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .organizer)
                        .submitLabel(.next)
                        .onSubmit { focused = .session }
                        .accessibilityIdentifier("organizerName")
                }
            }
            LabeledField(title: L("Session name"), isFocused: focused == .session) {
                TextField(L("e.g. Open day in November"), text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                    .focused($focused, equals: .session)
                    .submitLabel(.done)
                    .onSubmit(advance)
                    .accessibilityIdentifier("sessionName")
            }
            card {
                DatePicker(L("Date"), selection: $draft.date, displayedComponents: .date)
                    .environment(\.locale, Language.current.locale)
                    .font(.textBody).foregroundStyle(Color.inkPrimary)
                    .tint(Color.accent)
                Toggle(isOn: $draft.endReminder) {
                    Label(L("End reminder"), systemImage: "bell").font(.textBody).foregroundStyle(Color.inkPrimary)
                }
                .tint(Color.accent)
                if draft.endReminder {
                    DatePicker(L("End time"), selection: $draft.endTime, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Language.current.locale)
                        .font(.textBody).foregroundStyle(Color.inkPrimary)
                        .tint(Color.accent)
                }
            }
        }
    }

    private var programs: some View {
        ProgramsSection(showsTitle: false)
            .padding(.horizontal, Space.l)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private var targets: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            card(title: L("Expected attendance")) {
                targetRow(L("Pre-registered")) { QuantityControl(value: $draft.preRegistered, range: 0...5000, step: 5) }
            }
            card(title: L("Meeting rate target")) {
                targetRow(L("Low target")) { QuantityControl(value: $draft.rdvTargetLow, range: 0...100, step: 5, suffix: " %") }
                targetRow(L("High target")) { QuantityControl(value: $draft.rdvTargetHigh, range: 0...100, step: 5, suffix: " %") }
            }
            if !appState.programs.isEmpty {
                card(title: L("By program")) {
                    ForEach(appState.programs) { program in
                        targetRow(program.name, color: program.swiftUIColor) {
                            QuantityControl(
                                value: Binding(
                                    get: { draft.programObjectives[program.id] ?? 0 },
                                    set: { draft.programObjectives[program.id] = $0 > 0 ? $0 : nil }
                                ),
                                range: 0...5000, step: 5
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    /// The one container every page uses for grouped controls.
    private func card<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let title { Text(title).font(.textSub.weight(.medium)).foregroundStyle(Color.inkTertiary) }
            VStack(alignment: .leading, spacing: Space.m) { content() }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }

    private func targetRow<Control: View>(_ title: String, color: Color? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Space.m) {
            if let color { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10) }
            Text(title).font(.textBody).foregroundStyle(Color.inkPrimary).lineLimit(1)
            Spacer(minLength: Space.s)
            control()
        }
    }

    // MARK: Actions

    private func advance() {
        guard canContinue else { return }
        Haptics.selection()
        errorText = nil
        if page < Self.pageCount - 1 {
            page += 1
            return
        }
        isCreating = true
        focused = nil
        Task {
            do {
                try await onCreate(draft)
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
                isCreating = false
            }
        }
    }
}

/// "Create a session" from inside the app: the same three pages as the first launch, with the same back button.
struct NewSessionSheet: View {
    @Binding var page: Int
    let onCreate: (SessionDraft) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { if page > 0 { page -= 1 } else { dismiss() } } label: {
                    Image(systemName: page > 0 ? "chevron.left" : "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCard2, in: Circle())
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(page > 0 ? L("Back") : L("Close"))
                .padding(.leading, -Space.s)
                Spacer()
            }
            .frame(minHeight: 55)
            SessionCreationFlow(page: $page, onCreate: onCreate)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .background(PaperBackground())
    }
}
