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
                // Leaving onboarding: it recedes while the app arrives from below.
                OnboardingView().transition(.shift(scale: 1.04))
            case .ready:
                MainTabView().transition(.shift(y: 28, scale: 0.98))
            }
        }
        .animation(.curve(Motion.large), value: appState.phase)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [BottomTabBar.Item] {
        var items: [BottomTabBar.Item] = [.init(tab: .prospects, title: "Prospects", icon: "person.2")]
        // Agents never see statistics: only the organizer, who has the whole event once imports are done.
        if appState.isAdmin { items.append(.init(tab: .dashboard, title: "Stats", icon: "chart.bar.xaxis")) }
        items.append(.init(tab: .archive, title: "Archive", icon: "archivebox"))
        let exchange: (String, String) = appState.isAdmin ? (L("Collect"), "tray.and.arrow.down")
            : (appState.isConseiller ? (L("Inbox"), "arrow.down.circle") : (L("Send"), "paperplane"))
        items.append(.init(tab: .exchange, title: exchange.0, icon: exchange.1))
        return items
    }

    private func content(for tab: AppState.MainTab) -> some View {
        NavigationStack {
            switch tab {
            case .prospects: SessionListView()
            case .dashboard: DashboardView()
            case .archive:   ArchiveView()
            case .exchange:  ExchangeView()
            }
        }
    }

    var body: some View {
        @Bindable var state = appState
        let tabs = items.map(\.tab)
        let selectedIndex = tabs.firstIndex(of: appState.selectedTab) ?? 0
        // Every tab stays alive (so each keeps its scroll position and state). Changing tab slides the
        // current one out and the next one in along the same axis as the bar below.
        ZStack {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let active = tab == appState.selectedTab
                content(for: tab)
                    .themedNavigationBar()
                    .opacity(active ? 1 : 0)
                    .offset(x: active || reduceMotion ? 0 : (index < selectedIndex ? -16 : 16))
                    .allowsHitTesting(active)
                    .accessibilityHidden(!active)
                    .zIndex(active ? 1 : 0)
            }
        }
        .animation(.curve(Motion.tab), value: appState.selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let showsAdd = appState.selectedTab == .prospects && appState.canEditProspects
            HStack(spacing: Space.m) {
                BottomTabBar(selection: $state.selectedTab, items: items)
                if showsAdd {
                    AddProspectButton { appState.route = .newProspect }
                        .transition(.pop)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.s)
            // The bar changes width when the add button comes or goes: its icons glide with it instead of jumping.
            .animation(.curve(Motion.tab), value: showsAdd)
            .animation(.curve(Motion.tab), value: appState.selectedTab)
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
        .accessibilityLabel(L("New prospect"))
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
