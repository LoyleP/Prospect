// Views/Components/ProspectSavedBurst.swift
// The moment a new prospect is saved: a check draws itself inside a filled disc, a ring opens around it and
// flat confetti leaves in every direction. About 0.8 s in all, because agents add prospects back to back.
// Flat shapes only (no gradients, no glow). With "Reduce Motion" on, only the disc and the check appear.
import SwiftUI

struct ProspectSavedBurst: View {
    /// The prospect's program colour, mixed in with the accent for the confetti.
    var tint: Color = .accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false

    private static let count = 14
    private let discSize: CGFloat = 96

    var body: some View {
        ZStack {
            Color.surfaceBackground.opacity(0.94)

            ZStack {
                if !reduceMotion {
                    Circle()
                        .strokeBorder(Color.accent.opacity(go ? 0 : 0.5), lineWidth: go ? 1 : 6)
                        .frame(width: discSize, height: discSize)
                        .scaleEffect(go ? 2.1 : 1)
                        .animation(.easeOut(duration: 0.55).delay(0.08), value: go)

                    ForEach(0..<Self.count, id: \.self) { index in particle(index) }
                }

                Circle()
                    .fill(Color.accent)
                    .frame(width: discSize, height: discSize)
                    .scaleEffect(go ? 1 : 0.4)
                    .opacity(go ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.58), value: go)

                Check()
                    .trim(from: 0, to: go ? 1 : 0)
                    .stroke(Color.onAccent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .frame(width: 38, height: 30)
                    .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.26).delay(reduceMotion ? 0 : 0.14), value: go)
            }
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .onAppear { go = true }
    }

    /// One piece of confetti: a dot or a short bar that flies out along its own angle and fades.
    private func particle(_ index: Int) -> some View {
        let angle = Double(index) / Double(Self.count) * 2 * .pi + (index.isMultiple(of: 2) ? 0 : 0.12)
        let distance: CGFloat = index.isMultiple(of: 2) ? 118 : 92
        let color: Color = switch index % 3 { case 0: .accent; case 1: tint; default: .accent.opacity(0.55) }
        let isBar = index.isMultiple(of: 3)
        return Group {
            if isBar { Capsule().fill(color).frame(width: 5, height: 14) }
            else { Circle().fill(color).frame(width: 8, height: 8) }
        }
        .rotationEffect(.radians(angle + .pi / 2))
        .offset(x: go ? cos(angle) * distance : 0, y: go ? sin(angle) * distance : 0)
        .scaleEffect(go ? 0.4 : 1)
        .opacity(go ? 0 : 1)
        .animation(.easeOut(duration: 0.6).delay(0.12 + Double(index % 4) * 0.025), value: go)
    }

    /// The check mark's path, drawn from its short stroke to its long one.
    private struct Check: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1))
            p.addLine(to: CGPoint(x: rect.width * 0.36, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return p
        }
    }
}

#Preview { ProspectSavedBurst(tint: .orange) }
