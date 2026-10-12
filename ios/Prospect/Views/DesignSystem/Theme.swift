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
