// Views/Components/OnboardingAnimation.swift
// The loop on the first screen: an organizer's invitation, agents collecting, encrypted files coming back.
// The artboard ("Welcome" in Resources/onboarding.riv) has no text and a transparent background.
import RiveRuntime
import SwiftUI

struct OnboardingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: RiveViewModel?

    var body: some View {
        Group {
            if let model { model.view() }
        }
        .accessibilityHidden(true)
        .onAppear {
            if model == nil { model = Self.makeModel() }
            if reduceMotion {
                // The first frames are the organizer's QR alone: a still image.
                Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    model?.pause()
                }
            } else {
                model?.play()
            }
        }
        .onDisappear { model?.pause() }
    }

    /// `RiveViewModel` traps on a missing file, so check first and show nothing instead.
    private static func makeModel() -> RiveViewModel? {
        guard Bundle.main.url(forResource: "onboarding", withExtension: "riv") != nil else { return nil }
        return RiveViewModel(
            fileName: "onboarding", stateMachineName: "Welcome",
            fit: .contain, alignment: .center, autoPlay: true, loadCdn: false
        )
    }
}
