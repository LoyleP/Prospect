// Views/Components/SurfaceModifiers.swift
// App-wide surface theming for List/Form/ScrollView containers.
import SwiftUI

extension View {
    /// Themes a List or Form container: hides the system grouped background and
    /// paints the base surface behind it. Does NOT set row backgrounds —
    /// `.listRowBackground()` is a no-op when applied to the List/Form container
    /// itself; it must be applied per-row or per-ForEach/Section inside the content
    /// builder. Use `.themedRowBackground()` for that.
    func themedListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.surfaceBackground)
    }

    /// Themes a plain ScrollView-based screen (no List/Form rows).
    func themedScrollBackground() -> some View {
        self.background(Color.surfaceBackground)
    }

    /// Default row/card background. Apply inside a List's content builder —
    /// directly on a row, or chained after a ForEach/Section — never on the List itself.
    func themedRowBackground() -> some View {
        self.listRowBackground(Color.surfaceCard)
    }

    /// Pins the navigation bar background on iOS 26+.
    ///
    /// iOS 26 changed the navigation bar's compositing order: an explicit background
    /// *colour* is drawn in front of the title instead of behind it. That applies to
    /// `UINavigationBarAppearance.backgroundColor` AND to SwiftUI's
    /// `toolbarBackground(_:for:)` — the title still reserves its space but is never
    /// painted. So no colour is set here; only the visibility. The bar keeps its
    /// system material, which already reads as `Color.surfaceBackground` under the
    /// app's forced dark scheme.
    ///
    /// No-op pre-iOS 26, where the UIKit appearance proxy in `YstudentsApp` owns the bar.
    func themedNavigationBar() -> some View {
        self.modifier(ThemedNavigationBarModifier())
    }
}

private struct ThemedNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            content
        }
    }
}
