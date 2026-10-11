// ContentView.swift
// Root router: login → organization onboarding → main tabs.
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.phase {
        case .signedOut:
            LoginView()
        case .loading:
            LaunchView()
        case .needsOrganization:
            CreateOrganizationView(isOnboarding: true)
        case .ready:
            MainTabView()
                // Fresh view models (and data) whenever the organization changes.
                .id(appState.currentOrganization?.id)
        }
    }
}

private struct LaunchView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            if let error = appState.loadError {
                ContentUnavailableView(
                    "Connexion impossible",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
                Button("Réessayer") { Task { await appState.bootstrap() } }
                    .buttonStyle(.borderedProminent)
                Button("Se déconnecter", role: .destructive) { Task { await appState.signOut() } }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceBackground.ignoresSafeArea())
        .task { await appState.bootstrap() }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            NavigationStack {
                SessionListView()
                    .themedNavigationBar()
            }
            .tabItem { Label("Prospects", systemImage: "person.2") }

            NavigationStack {
                DashboardView()
                    .themedNavigationBar()
            }
            .tabItem { Label("Tableau de bord", systemImage: "chart.bar.fill") }

            NavigationStack {
                ArchiveView()
                    .themedNavigationBar()
            }
            .tabItem { Label("Archive", systemImage: "archivebox") }

            if appState.isAdmin {
                NavigationStack {
                    EquipeView()
                        .themedNavigationBar()
                }
                .tabItem { Label("Équipe", systemImage: "building.2") }
            }
        }
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
