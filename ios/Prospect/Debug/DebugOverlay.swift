// Debug/DebugOverlay.swift
// A draggable floating button that opens the debug menu from ANY screen: login, onboarding,
// tabs, and on top of sheets and alerts. It lives in its own UIWindow above the app, so it does
// not depend on which SwiftUI screen is showing. Debug builds only.
#if DEBUG
import SwiftUI
import UIKit

@MainActor
final class DebugOverlay {
    static let shared = DebugOverlay()

    private var window: DebugOverlayWindow?
    private weak var appState: AppState?
    private let positionKey = "debug.buttonPosition"

    // MARK: Install

    /// Idempotent. Call once the app has a window scene (ContentView does, on appear).
    func install(appState: AppState) {
        self.appState = appState
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let controller = OverlayController()
        controller.onTap = { [weak self] in self?.presentMenu() }
        controller.positionKey = positionKey

        let window = DebugOverlayWindow(windowScene: scene)
        window.windowLevel = .alert + 1          // above sheets, alerts and the keyboard
        window.backgroundColor = .clear
        window.rootViewController = controller
        window.overlayController = controller
        window.isHidden = false                  // visible, but never key: it does not steal focus
        self.window = window
        refreshBadge()
    }

    // MARK: Menu

    func presentMenu() {
        guard let window, let appState, let root = window.rootViewController, root.presentedViewController == nil else { return }
        Haptics.tap()
        let host = UIHostingController(rootView: DebugMenuView().environment(appState).preferredColorScheme(.dark))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(Color.surfaceBackground)
        host.modalPresentationStyle = .pageSheet
        host.sheetPresentationController?.detents = [.large()]
        host.sheetPresentationController?.prefersGrabberVisible = true
        root.present(host, animated: true)
    }

    /// An amber dot on the button while the app runs on demo data, not the real API.
    func refreshBadge() {
        (window?.rootViewController as? OverlayController)?.setDemoBadge(DebugLaunch.active != nil)
    }
}

// MARK: - Window

/// Full-screen, but only the button is touchable (unless the menu is open).
final class DebugOverlayWindow: UIWindow {
    weak var overlayController: OverlayController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if rootViewController?.presentedViewController != nil { return super.hitTest(point, with: event) }
        guard let button = overlayController?.button, button.frame.insetBy(dx: -10, dy: -10).contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Controller

final class OverlayController: UIViewController {
    let button = UIView()
    var onTap: () -> Void = {}
    var positionKey = ""

    private let size: CGFloat = 55
    private let badge = UIView()
    private var hasPlaced = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        button.frame = CGRect(x: 0, y: 0, width: size, height: size)
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.backgroundColor = UIColor(Color.inkPrimary).withAlphaComponent(0.92)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Menu debug"
        button.accessibilityTraits = .button
        button.accessibilityIdentifier = "debugButton"

        let icon = UIImageView(image: UIImage(systemName: "ladybug.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
        icon.tintColor = UIColor(Color.onInk)
        icon.frame = button.bounds
        icon.contentMode = .center
        button.addSubview(icon)

        badge.frame = CGRect(x: size - 12, y: -3, width: 13, height: 13)
        badge.layer.cornerRadius = 6.5
        badge.backgroundColor = UIColor(Color.warning)
        badge.layer.borderWidth = 2
        badge.layer.borderColor = UIColor(Color.surfaceBackground).cgColor
        badge.isHidden = true
        button.addSubview(badge)

        button.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        view.addSubview(button)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasPlaced, view.bounds.width > 0 else { return }
        hasPlaced = true
        if let saved = UserDefaults.standard.array(forKey: positionKey) as? [Double], saved.count == 2 {
            button.center = clamped(CGPoint(x: saved[0], y: saved[1]))
        } else {
            // First launch: right edge, just below the middle (clear of headers, the tab bar and the add button).
            button.center = CGPoint(x: view.bounds.width - size / 2 - 8, y: view.bounds.height * 0.57)
        }
    }

    func setDemoBadge(_ on: Bool) { badge.isHidden = !on }

    @objc private func tapped() { onTap() }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            button.center = clamped(CGPoint(x: button.center.x + t.x, y: button.center.y + t.y))
            gesture.setTranslation(.zero, in: view)
        case .ended, .cancelled:
            // Snap to the nearest side edge.
            let x = button.center.x < view.bounds.midX ? size / 2 + 8 : view.bounds.width - size / 2 - 8
            let animator = UIViewPropertyAnimator(duration: 0.35, timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.5, y: 0), controlPoint2: CGPoint(x: 0, y: 1)))
            animator.addAnimations { self.button.center = self.clamped(CGPoint(x: x, y: self.button.center.y)) }
            animator.startAnimation()
            UserDefaults.standard.set([Double(x), Double(button.center.y)], forKey: positionKey)
        default:
            break
        }
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        let insets = view.safeAreaInsets
        return CGPoint(
            x: min(max(p.x, size / 2 + 4), view.bounds.width - size / 2 - 4),
            y: min(max(p.y, insets.top + size / 2), view.bounds.height - insets.bottom - size / 2)
        )
    }
}
#endif
