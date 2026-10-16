// Views/OnboardingView.swift
// First launch. No account: choose to organize an event, or join one by scanning the organizer's invitation.
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    private enum Step: Int { case choose, organize, join }
    @State private var step: Step = .choose
    /// Which way the last step change went, so the next screen enters from the side we are heading to.
    @State private var forward = true
    /// The joining agent or advisor's own name.
    @State private var name = ""
    private var cleanName: String { name.trimmingCharacters(in: .whitespaces) }
    /// Which of the three session-creation pages is showing.
    @State private var organizePage = 0
    @State private var invitation: Invitation?
    /// Who is joining: an agent records prospects, a conseiller receives what the organizer shares.
    @State private var joinRole: Role = .agent
    @State private var pasted = ""
    @State private var errorText: String?
    @FocusState private var focused: Field?
    private enum Field { case name, paste }

    /// A plain slide: the next step comes in from the trailing edge and the current one leaves by the leading edge.
    /// Going back reverses both, so the path is always the same one walked backwards.
    private var slide: AnyTransition {
        forward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 0) {
                header
                ZStack(alignment: .top) {
                    switch step {
                    case .choose:   choose.transition(slide)
                    case .organize: organize.transition(slide)
                    case .join:     join.transition(slide)
                    }
                }
                .clipped()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
        }
        .animation(.curve(Motion.standard), value: step)
        .animation(.curve(Motion.standard), value: invitation)
        .animation(.curve(Motion.micro), value: errorText)
        .onAppear(perform: applyIntent)
        .onChange(of: appState.pendingInvitation) { _, _ in applyIntent() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if step == .choose {
                Wordmark(size: 28)
            } else {
                Button { back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCard2, in: Circle())
                        .frame(width: 55, height: 55)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Back"))
                .padding(.leading, -Space.s)
            }
            Spacer()
            if step == .choose { LanguageMenu().padding(.trailing, -Space.s) }
        }
        .frame(minHeight: 55)
    }

    // MARK: Choose

    private var choose: some View {
        VStack(spacing: Space.s) {
            OnboardingAnimation()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, Space.s)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(L("Collect your prospects")).font(.displayM).foregroundStyle(Color.inkPrimary)
                Text(L("No account: everything stays on your phones"))
                    .font(.textBody).foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Space.m)
            .appears(0)
            choiceRow(icon: "plus", title: L("Create a session")) { go(.organize) }
                .accessibilityIdentifier("organize")
                .appears(1)
            choiceRow(icon: "qrcode.viewfinder", title: L("Join a session")) { go(.join) }
                .accessibilityIdentifier("join")
                .appears(2)
        }
        .padding(.bottom, Space.l)
        .frame(maxHeight: .infinity)
    }

    private func choiceRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.accent)
                    .frame(width: 44, height: 44)
                    .background(Color.accent.opacity(0.14), in: Circle())
                Text(title).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 72)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }

    // MARK: Organize

    private var organize: some View {
        SessionCreationFlow(page: $organizePage, askOrganizerName: true) { draft in
            try await appState.createFirstSession(draft)
        }
    }

    // MARK: Join

    private var join: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(L("Join a session")).font(.displayL).foregroundStyle(Color.inkPrimary)
            ZStack(alignment: .top) {
                if let invitation {
                    VStack(alignment: .leading, spacing: Space.l) {
                        eventCard(invitation)
                        HStack(spacing: Space.s) {
                            ChoiceChip(title: "Agent", isSelected: joinRole == .agent) { joinRole = .agent }
                            ChoiceChip(title: L("Advisor"), isSelected: joinRole == .conseillerFormation) { joinRole = .conseillerFormation }
                        }
                        TextField("", text: $name, prompt: Text(L("Your name")).foregroundStyle(Color.inkTertiary))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.inkPrimary)
                            .tint(Color.accent)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .focused($focused, equals: .name)
                            .submitLabel(.join)
                            .onSubmit { confirmJoin(invitation) }
                            .accessibilityIdentifier("agentName")
                        Spacer(minLength: Space.l)
                        Button(L("Join")) { confirmJoin(invitation) }
                            .buttonStyle(.primary)
                            .disabled(cleanName.isEmpty)
                            .accessibilityIdentifier("confirmJoin")
                            .padding(.bottom, Space.s)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(slide)
                } else {
                    VStack(alignment: .leading, spacing: Space.m) {
                        viewfinder
                        pasteField
                        if let errorText { InlineError(text: errorText).transition(.drop) }
                    }
                    .transition(slide)
                }
            }
            .clipped()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The camera is the screen: a dashed frame over the live view.
    private var viewfinder: some View {
        ZStack {
            QRScannerView { code in tryInvitation(code, fromScan: true) }
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                .padding(36)
                .allowsHitTesting(false)
        }
        .frame(height: 340)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var pasteField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "link").foregroundStyle(Color.inkTertiary)
            TextField("", text: $pasted, prompt: Text("prospect://…").foregroundStyle(Color.inkTertiary))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .paste)
                .onChange(of: pasted) { _, text in tryInvitation(text) }
            Button {
                Haptics.tap()
                if let text = UIPasteboard.general.string { pasted = text }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 44, height: 55)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("Paste"))
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.xs)
        .frame(minHeight: 55)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(errorText != nil ? Color.error : (focused == .paste ? Color.accent.opacity(0.7) : Color.clear), lineWidth: 1.5)
        }
    }

    private func eventCard(_ i: Invitation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(i.name).font(.textHeadline).foregroundStyle(Color.inkPrimary)
            Text(i.organizerName).font(.textFootnote).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    // MARK: Actions

    private func applyIntent() {
        if let pending = appState.pendingInvitation {
            invitation = pending
            step = .join
        } else if let intent = appState.onboardingIntent {
            step = intent == .organize ? .organize : .join
            appState.onboardingIntent = nil
        }
    }

    private func back() {
        errorText = nil
        if step == .organize, organizePage > 0 {
            organizePage -= 1
        } else if step == .join, invitation != nil {
            invitation = nil; pasted = ""
            appState.pendingInvitation = nil
        } else {
            go(.choose)
        }
    }

    private func go(_ next: Step) {
        forward = next.rawValue > step.rawValue
        focused = nil
        Haptics.selection()
        withAnimation(.curve(Motion.standard)) { step = next }
        if next == .organize { organizePage = 0 }
    }

    private func tryInvitation(_ text: String, fromScan: Bool = false) {
        guard !text.isEmpty else { errorText = nil; return }
        if let found = Invitation(text: text) {
            forward = true
            Haptics.success()
            invitation = found
            errorText = nil
            focused = .name
        } else if fromScan {
            errorText = L("This code isn't a Prospect invitation.")
        } else if text.count > 12 {
            errorText = L("This link isn't a Prospect invitation.")
        }
    }

    private func confirmJoin(_ invitation: Invitation) {
        do {
            try appState.startAsAgent(name: cleanName, invitation: invitation, role: joinRole)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
