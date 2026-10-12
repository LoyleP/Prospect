// Views/DesignSystem/Theme.swift
// Spacing, radii, haptics, the paper background, the wordmark, rules, and the ticket.
import SwiftUI
import UIKit

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Horizontal screen margin.
    static let gutter: CGFloat = 20
}

/// Deliberately small. Soft, bubbly corners are the loudest "generated" tell.
enum Radius {
    static let s: CGFloat = 6
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
}

/// The one easing curve of the app: cubic-bezier(0.5, 0, 0, 1). Every animation and transition uses it,
/// at different durations. Never use `.snappy`, `.spring`, `.easeOut` or a bare `withAnimation`.
extension Animation {
    static func curve(_ duration: Double = 0.3) -> Animation {
        .timingCurve(0.5, 0, 0, 1, duration: duration)
    }
}

/// Durations by how much changes on screen (motion guidance: small ≈ 150-200 ms, standard ≈ 300 ms,
/// full screen ≈ 375-400 ms). Things that leave take a little less time than things that arrive.
enum Motion {
    static let micro = 0.18
    /// Switching tabs happens all the time: brief and small.
    static let tab = 0.22
    static let standard = 0.3
    static let large = 0.4
    static let exit = 0.24
    /// Gap between items that arrive together. Kept tiny: staggering must not make people wait.
    static let stagger = 0.05
}

/// A transition is never a bare fade: it also moves or scales from where the thing comes from.
/// With "Reduce Motion" on, the movement is dropped and only the fade stays.
private struct Shift: ViewModifier {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(reduceMotion ? 1 : scale)
            .offset(x: reduceMotion ? 0 : x, y: reduceMotion ? 0 : y)
    }
}

extension AnyTransition {
    static func shift(x: CGFloat = 0, y: CGFloat = 0, scale: CGFloat = 1) -> AnyTransition {
        .modifier(active: Shift(x: x, y: y, scale: scale, opacity: 0), identity: Shift())
    }

    /// Content that arrives from below and settles.
    static var rise: AnyTransition { .shift(y: 14, scale: 0.985) }
    /// Something that appears out of a point (the add button).
    static var pop: AnyTransition { .shift(scale: 0.6) }
    /// A banner that slides in from the top edge it belongs to.
    static var drop: AnyTransition { .shift(y: -16) }

    /// Shared axis (horizontal): the next step enters from the side the person is heading to, the previous one leaves the other way.
    static func axis(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .shift(x: forward ? 24 : -24),
            removal: .shift(x: forward ? -16 : 16)
        )
    }
}

/// Staggered entrance when a screen's content first shows: each item rises a little after the previous one.
private struct Appears: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.curve(Motion.standard).delay(Double(order) * Motion.stagger)) { shown = true }
            }
    }
}

extension View {
    func appears(_ order: Int = 0) -> some View { modifier(Appears(order: order)) }
}

/// Light, intentional haptics. Always prefer these over ad-hoc generators.
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// Flat paper. No gradients, no glow.
struct PaperBackground: View {
    var body: some View {
        Color.surfaceBackground.ignoresSafeArea()
    }
}

// MARK: - Wordmark

/// "Prospect." in heavy sans, with the full stop in the signal colour. The whole logo.
struct Wordmark: View {
    var size: CGFloat = 26

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("Prospect")
                .foregroundStyle(Color.inkPrimary)
            Text(".")
                .foregroundStyle(Color.accent)
        }
        .font(.system(size: size, weight: .heavy))
        .tracking(-size * 0.02)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prospect")
    }
}

// MARK: - Rules & cards

/// A hairline.
struct Rule: View {
    var strong = false

    var body: some View {
        Rectangle()
            .fill(strong ? Color.ruleStrong : Color.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A flat, hairline-bordered surface. Prefer ruled lines; use this sparingly.
    func card(padding: CGFloat = Space.l, radius: CGFloat = Radius.l) -> some View {
        self
            .padding(padding)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.rule, lineWidth: 1)
            }
    }
}

// MARK: - Ticket

/// A rounded rectangle with two half-circle bites out of its sides (horizontal perforation)
/// or out of its top and bottom (vertical perforation): an admission ticket.
struct TicketShape: Shape {
    enum Perforation {
        case horizontal(y: CGFloat)   // notches on the left and right edges at this y
        case vertical(x: CGFloat)     // notches on the top and bottom edges at this x
    }

    var perforation: Perforation
    var cornerRadius: CGFloat = Radius.l
    var notchRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let base = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        let d = notchRadius * 2
        switch perforation {
        case .horizontal(let y):
            return base
                .subtracting(Path(ellipseIn: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: d, height: d)))
                .subtracting(Path(ellipseIn: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: d, height: d)))
        case .vertical(let x):
            return base
                .subtracting(Path(ellipseIn: CGRect(x: x - notchRadius, y: rect.minY - notchRadius, width: d, height: d)))
                .subtracting(Path(ellipseIn: CGRect(x: x - notchRadius, y: rect.maxY - notchRadius, width: d, height: d)))
        }
    }
}

/// Content above and a stub below, torn along a dashed line.
struct TicketStack<Top: View, Stub: View>: View {
    @ViewBuilder var top: () -> Top
    @ViewBuilder var stub: () -> Stub

    var body: some View {
        VStack(spacing: 0) {
            top()
            Rule().padding(.horizontal, Space.l)
            stub()
        }
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// A leading stub and content, torn along a vertical dashed line.
struct TicketRow<Stub: View, Body_: View>: View {
    var emphasized = false
    @ViewBuilder var stub: () -> Stub
    @ViewBuilder var content: () -> Body_
    private let notch: CGFloat = 7
    @State private var stubWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            stub()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stubWidth = $0 }
            Line(vertical: true).stroke(Color.ruleStrong.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 1)
                .padding(.vertical, notch + 4)
                .padding(.horizontal, notch - 0.5)
            content()
        }
        .background(TicketShape(perforation: .vertical(x: stubWidth + notch), notchRadius: notch).fill(Color.surfaceCard))
        .overlay(TicketShape(perforation: .vertical(x: stubWidth + notch), notchRadius: notch)
            .stroke(emphasized ? Color.ruleStrong : Color.rule, lineWidth: emphasized ? 1.75 : 1))
    }
}

private struct Line: Shape {
    var vertical = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if vertical { p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
        else { p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        return p
    }
}
