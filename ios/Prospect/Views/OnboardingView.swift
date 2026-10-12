// Views/OnboardingView.swift
// First launch. No account: choose to organize an event, or join one by scanning the organizer's invitation.
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    private enum Step { case choose, organize, join }
    @State private var step: Step = .choose
    @State private var name = ""
    @State private var eventLabel = "Événement"
    @State private var customLabel = ""
    @State private var invitation: Invitation?
    @State private var pasted = ""
    @State private var showScanner = false
    @State private var errorText: String?
    @FocusState private var focused: Field?
    private enum Field { case name, custom, paste }

    private static let labels = ["Événement", "JPO", "Salon", "Forum", "Portes ouvertes"]
    private var cleanName: String { name.trimmingCharacters(in: .whitespaces) }
    private var cleanLabel: String {
        let custom = customLabel.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? eventLabel : custom
    }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 0) {
                header
                switch step {
                case .choose:   choose
                case .organize: organize
                case .join:     join
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
        }
        .animation(.curve(0.3), value: step)
        .animation(.curve(0.25), value: invitation)
        .animation(.curve(0.2), value: errorText)
        .onAppear(perform: applyIntent)
        .onChange(of: appState.pendingInvitation) { _, _ in applyIntent() }
        .sheet(isPresented: $showScanner) { scanner }
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
                .accessibilityLabel("Retour")
                .padding(.leading, -Space.s)
            }
            Spacer()
        }
        .frame(minHeight: 55)
    }

    // MARK: Choose

    private var choose: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Vos prospects restent sur vos téléphones")
                    .font(.displayL)
                    .foregroundStyle(Color.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Aucun compte, aucun serveur.")
                    .font(.textBody)
                    .foregroundStyle(Color.inkSecondary)
            }
            VStack(spacing: Space.s) {
                choiceRow(icon: "flag", title: "Organiser un événement", subtitle: "Je récupère les prospects de l'équipe") {
                    step = .organize; focused = .name
                }
                .accessibilityIdentifier("organize")
                choiceRow(icon: "qrcode.viewfinder", title: "Rejoindre un événement", subtitle: "Je scanne l'invitation de l'organisateur") {
                    step = .join
                }
                .accessibilityIdentifier("join")
            }
        }
        .padding(.top, Space.l)
    }

    private func choiceRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.accent)
                    .frame(width: 44, height: 44)
                    .background(Color.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                    Text(subtitle).font(.textFootnote).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 80)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }

    // MARK: Organize

    private var organize: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Organiser").font(.displayL).foregroundStyle(Color.inkPrimary)
            LabeledField(title: "Votre nom", isFocused: focused == .name) {
                TextField("Camille Martin", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .name)
                    .accessibilityIdentifier("organizerName")
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Vos événements s'appellent").font(.textSub.weight(.medium)).foregroundStyle(Color.inkTertiary)
                PillFlowLayout(spacing: Space.s) {
                    ForEach(Self.labels, id: \.self) { label in
                        ChoiceChip(title: label, isSelected: customLabel.isEmpty && eventLabel == label) {
                            eventLabel = label; customLabel = ""
                        }
                    }
                }
                LabeledField(title: "Autre", isFocused: focused == .custom) {
                    TextField(eventLabel, text: $customLabel)
                        .textInputAutocapitalization(.sentences)
                        .focused($focused, equals: .custom)
                }
            }
            Spacer(minLength: Space.l)
            Button("Continuer") {
                appState.startOrganizing(name: cleanName, eventLabel: cleanLabel)
            }
            .buttonStyle(.primary)
            .disabled(cleanName.isEmpty)
            .accessibilityIdentifier("continueOrganize")
            .padding(.bottom, Space.s)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Join

    private var join: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Rejoindre").font(.displayL).foregroundStyle(Color.inkPrimary)
            if let invitation {
                eventCard(invitation)
                LabeledField(title: "Votre nom", isFocused: focused == .name) {
                    TextField("Hugo Petit", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .accessibilityIdentifier("agentName")
                }
                Spacer(minLength: Space.l)
                Button("Rejoindre") { confirmJoin(invitation) }
                    .buttonStyle(.primary)
                    .disabled(cleanName.isEmpty)
                    .accessibilityIdentifier("confirmJoin")
                    .padding(.bottom, Space.s)
            } else {
                Button { showScanner = true } label: {
                    Label("Scanner l'invitation", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("scan")
                LabeledField(title: "Ou coller le lien d'invitation", isFocused: focused == .paste, hasError: errorText != nil) {
                    TextField("prospect://join?…", text: $pasted)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .paste)
                        .onChange(of: pasted) { _, text in tryInvitation(text) }
                }
                if let errorText { InlineError(text: errorText) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func eventCard(_ i: Invitation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(i.name).font(.textHeadline).foregroundStyle(Color.inkPrimary)
            Text("Organisé par \(i.organizerName)").font(.textFootnote).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private var scanner: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerView { code in
                showScanner = false
                tryInvitation(code, fromScan: true)
            }
            .ignoresSafeArea()
            Button { showScanner = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
                    .frame(width: 55, height: 55)
                    .contentShape(Rectangle())
            }
            .padding(Space.m)
            .accessibilityLabel("Fermer")
        }
        .presentationDragIndicator(.visible)
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
        if step == .join, invitation != nil {
            invitation = nil; pasted = ""
            appState.pendingInvitation = nil
        } else {
            step = .choose
        }
    }

    private func tryInvitation(_ text: String, fromScan: Bool = false) {
        guard !text.isEmpty else { errorText = nil; return }
        if let found = Invitation(text: text) {
            invitation = found
            errorText = nil
            focused = .name
        } else if fromScan {
            errorText = "Ce code n'est pas une invitation Prospect."
        } else if text.count > 12 {
            errorText = "Ce lien n'est pas une invitation Prospect."
        }
    }

    private func confirmJoin(_ invitation: Invitation) {
        do {
            try appState.startAsAgent(name: cleanName, invitation: invitation)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
