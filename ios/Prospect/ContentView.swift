// ContentView.swift
// Root router: login → organization onboarding → main tabs.
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var toast: Toast?

    var body: some View {
        ZStack {
            switch appState.phase {
            case .onboarding:
                OnboardingView().transition(.opacity)
            case .ready:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.curve(0.4), value: appState.phase)
        // Rebuild everything after an import or a swap of the store (fresh view models, fresh data).
        .id(appState.epoch)
        .toast($toast)
        .onChange(of: appState.importMessage) { _, text in
            if let text { toast = Toast(message: text, style: .info); appState.importMessage = nil }
        }
        .onOpenURL { appState.handleIncoming($0) }
        .debugMenu()
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
        items.append(.init(tab: .exchange, title: appState.isAdmin ? "Collecte" : "Envoi",
                           icon: appState.isAdmin ? "tray.and.arrow.down" : "paperplane"))
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

            NavigationStack {
                ExchangeView()
                    .themedNavigationBar()
            }
            .toolbarVisibility(.hidden, for: .tabBar)
            .tag(AppState.MainTab.exchange)
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

#Preview("App — Organisateur") {
    ContentView()
        .environment(AppState.preview(.organizerFull))
}

#Preview("App — Agent") {
    ContentView()
        .environment(AppState.preview(.agentFull))
}
