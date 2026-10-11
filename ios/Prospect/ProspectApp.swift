// ProspectApp.swift
import SwiftUI
import UIKit

@main
struct ProspectApp: App {
    @State private var appState = AppState()

    init() {
        Font.registerGeistFonts()
        Self.configureNavigationBarAppearance()
        Self.configureTabBarAppearance()
    }

    private static func configureNavigationBarAppearance() {
        // iOS 26 draws an explicit navigation bar background colour in FRONT of the
        // title — a Liquid Glass compositing regression. It applies to
        // UINavigationBarAppearance.backgroundColor and to SwiftUI's
        // toolbarBackground(_:for:) alike, so there is no way to tint the bar without
        // erasing the title. On iOS 26 the bar is therefore left entirely alone;
        // `.themedNavigationBar()` only pins its visibility. Since the app forces
        // .dark colorScheme, the system material and default title colour already
        // match the theme.
        guard #unavailable(iOS 26.0) else { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.surfaceBackground)

        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.gray100)]
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Color.gray100)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(Color.accent)
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.surfaceBackground)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = UIColor(Color.accent)
        UITabBar.appearance().unselectedItemTintColor = UIColor(Color.gray500)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
