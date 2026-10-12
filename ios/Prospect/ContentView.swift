// ContentView.swift
// Root router: login → organization onboarding → main tabs.
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            switch appState.phase {
            case .signedOut:
                LoginView().transition(.opacity)
            case .loading:
                LaunchView().transition(.opacity)
            case .needsOrganization:
                CreateOrganizationView(isOnboarding: true).transition(.opacity)
            case .ready:
                MainTabView()
                    // Fresh view models (and data) whenever the organization changes.
                    .id(appState.currentOrganization?.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.curve(0.4), value: appState.phase)
        // Rebuild everything when the backend is swapped (debug demo mode).
        .id(appState.epoch)
        .debugMenu()
    }
}

private struct LaunchView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            PaperBackground()
            if let error = appState.loadError {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Connexion\nimpossible.")
                        .font(.displayXL)
                        .foregroundStyle(Color.inkPrimary)
                    Text(error)
                        .font(.textBody)
                        .foregroundStyle(Color.inkSecondary)
                    VStack(spacing: Space.m) {
                        Button("Réessayer") { Task { await appState.bootstrap() } }
                            .buttonStyle(.primary)
                        Button("Se déconnecter") { Task { await appState.signOut() } }
                            .buttonStyle(.secondary)
                    }
                    .padding(.top, Space.s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.gutter)
            } else {
                VStack(spacing: Space.l) {
                    Wordmark(size: 40)
                    ProgressView().tint(Color.inkTertiary)
                }
            }
        }
        .task { await appState.bootstrap() }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    private var items: [BottomTabBar.Item] {
        var items: [BottomTabBar.Item] = [
            .init(tab: .prospects, title: "Prospects", icon: "person.2"),
            .init(tab: .dashboard, title: "Stats", icon: "chart.bar.xaxis"),
            .init(tab: .archive, title: "Archive", icon: "archivebox"),
        ]
        if appState.isAdmin { items.append(.init(tab: .team, title: "Équipe", icon: "building.2")) }
        return items
    }

    var body: some View {
        @Bindable var state = appState
        // The system tab bar is hidden: BottomTabBar (a capsule) and the add button replace it.
        TabView(selection: $state.selectedTab) {
            NavigationStack {
                SessionListView()
                    .themedNavigationBar()
            }
            .toolbarVisibility(.hidden, for: .tabBar)
            .tag(AppState.MainTab.prospects)

            NavigationStack {
                DashboardView()
                    .themedNavigationBar()
            }
            .toolbarVisibility(.hidden, for: .tabBar)
            .tag(AppState.MainTab.dashboard)

            NavigationStack {
                ArchiveView()
                    .themedNavigationBar()
            }
            .toolbarVisibility(.hidden, for: .tabBar)
            .tag(AppState.MainTab.archive)

            if appState.isAdmin {
                NavigationStack {
                    EquipeView()
                        .themedNavigationBar()
                }
                .toolbarVisibility(.hidden, for: .tabBar)
                .tag(AppState.MainTab.team)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: Space.m) {
                BottomTabBar(selection: $state.selectedTab, items: items)
                if appState.selectedTab == .prospects && appState.canEditProspects {
                    AddProspectButton { appState.route = .newProspect }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.s)
            .animation(.curve(0.25), value: appState.selectedTab)
            .ignoresSafeArea(.keyboard)
        }
        .ignoresSafeArea(.keyboard)
        .background(Color.surfaceBackground.ignoresSafeArea())
    }
}

/// The one indigo control, a round button beside the tab capsule.
struct AddProspectButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.onAccent)
                .frame(width: 66, height: 66)
                .background(Color.accent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        .accessibilityLabel("Nouveau prospect")
        .accessibilityIdentifier("addProspect")
    }
}

#Preview("App — Admin") {
    ContentView()
        .environment(AppState.preview(role: .admin))
}

#Preview("App — Agent") {
    ContentView()
        .environment(AppState.preview(nom: "Jean Dupont", role: .agent))
}
