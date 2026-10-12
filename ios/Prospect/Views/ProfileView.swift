// Views/ProfileView.swift
// Who you are on this phone: your name and role, what you recorded, settings (organizer), and a reset.
// Opened from the monogram on the Prospects tab.
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var showReset = false
    @State private var showSettings = false
    @State private var showJoin = false
    @State private var editingName = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                NumberedSection(number: "01", title: "Activité") {
                    HStack(alignment: .top, spacing: 0) {
                        stat("\(viewModel.totalProspects)", "prospects")
                        stat("\(viewModel.rdvCount)", "RDV")
                        stat("\(Int(viewModel.rdvRate.rounded())) %", "taux")
                    }
                    .opacity(viewModel.isLoading ? 0.35 : 1)
                    .animation(.curve(0.2), value: viewModel.isLoading)
                }

                VStack(spacing: 0) {
                    if appState.isAdmin {
                        row("Réglages", icon: "slider.horizontal.3") { showSettings = true }
                    } else {
                        row("Rejoindre un autre événement", icon: "qrcode.viewfinder") { showJoin = true }
                    }
                }
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))

                Button("Réinitialiser cet appareil") { showReset = true }
                    .buttonStyle(.secondary)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .background(PaperBackground())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceCard2, in: Circle())
                    .frame(width: 55, height: 55)
                    .contentShape(Rectangle())
            }
            .padding(Space.l)
            .accessibilityLabel("Fermer")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surfaceBackground)
        .sheet(isPresented: $showSettings) {
            OrganizationSettingsView()
                .presentationBackground(Color.surfaceBackground)
        }
        .sheet(isPresented: $showJoin) {
            JoinSheet().presentationBackground(Color.surfaceBackground)
        }
        .alert("Réinitialiser cet appareil ?", isPresented: $showReset) {
            Button("Réinitialiser", role: .destructive) {
                dismiss()
                appState.resetDevice()
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.l) {
            Monogram(name: appState.agentNom, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                if editingName {
                    TextField("Votre nom", text: $newName)
                        .font(.displayS)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                } else {
                    Button { newName = appState.agentNom; editingName = true; nameFocused = true } label: {
                        Text(appState.agentNom)
                            .font(.displayS)
                            .foregroundStyle(Color.inkPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                Stamp(text: appState.isAdmin ? "Organisateur" : "Agent", color: appState.isAdmin ? .adminAccent : .info)
            }
            Spacer(minLength: 40)
        }
        .padding(.top, Space.l)
    }

    private func commitName() {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { appState.updateIdentity(displayName: clean) }
        editingName = false
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: Space.m) {
                Image(systemName: icon).foregroundStyle(Color.inkSecondary).frame(width: 24)
                Text(title).font(.textBody).foregroundStyle(Color.inkPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.numeral(30))
                .foregroundStyle(Color.inkPrimary)
                .monospacedDigit()
            Text(label)
                .font(.textCaption.weight(.medium))
                .foregroundStyle(Color.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Profil — Organisateur") {
    Text("").sheet(isPresented: .constant(true)) { ProfileView() }
        .environment(AppState.preview(.organizerFull))
}
