// Views/Components/OnboardingAnimation.swift
// The loop on the first screen, drawn natively (no animation runtime): an organizer's invitation (QR),
// three agents collecting visitors, their encrypted files travelling back, and the organizer's dashboard.
// No text. One Canvas, one 9 s loop, the app's (0.5, 0, 0, 1) curve on every move.
import SwiftUI

struct OnboardingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var running = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running || reduceMotion)) { timeline in
            Canvas { ctx, size in
                // Reduce Motion: frame 0 is the organizer's QR alone, a still image.
                let frame = reduceMotion ? 0 : (timeline.date.timeIntervalSince(start) * 60)
                    .truncatingRemainder(dividingBy: OnboardingScene.length)
                OnboardingScene.draw(&ctx, in: size, frame: frame)
            }
        }
        .accessibilityHidden(true)
        .onAppear { start = Date(); running = true }
        .onDisappear { running = false }
    }
}

/// The storyboard, in frames at 60 fps (540 = 9 s) on a 360 × 520 artboard that is fitted and centered.
private enum OnboardingScene {
    static let length = 540.0
    static let artboard = CGSize(width: 360, height: 520)

    // MARK: Time helpers

    /// cubic-bezier(0.5, 0, 0, 1), the app's single easing curve.
    static func curve(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<20 {
            t = (lo + hi) / 2
            let bx = 1.5 * t * (1 - t) * (1 - t) + t * t * t
            if bx < x { lo = t } else { hi = t }
        }
        return 3 * (1 - t) * t * t + t * t * t
    }

    /// `v0` before `a`, `v1` after `b`, eased in between.
    static func ramp(_ f: Double, _ a: Double, _ b: Double, _ v0: Double = 0, _ v1: Double = 1) -> Double {
        v0 + (v1 - v0) * curve((f - a) / (b - a))
    }

    // MARK: Colours

    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color { Color(UIColor(hex: value, alpha: alpha)) }
    static let phone = hex(0x151516)
    static let phoneLine = hex(0x2A2B2E)
    static let ink = hex(0xF2F3F5, 0.9)
    static let gray = hex(0x8A8F98), light = hex(0xD0D6E0), teal = hex(0x5BC0D8), green = hex(0x4CC596)
    static var accent: Color { Color.accent }

    // MARK: Scene data

    static let agentX: [Double] = [70, 180, 290]
    static let agentY = 410.0
    static let organizer = CGPoint(x: 180, y: 120)
    /// Frame at which each agent's first visitor appears.
    static let firstVisitor: [Double] = [140, 155, 170]
    static let visitorColors: [[Color]] = [[gray, light, teal], [light, teal, green], [gray, teal, green]]
    static let visitorX: [Double] = [-24, 0, 24]
    static let rowY: [Double] = [-20, 0, 20]
    static let qrDots: [(Double, Double)] = [
        (-5.5, -23.5), (3.5, -23.5), (-4.5, -14.5), (6.5, -14.5), (-23.5, -5.5), (-13.5, -5.5), (-3.5, -5.5),
        (6.5, -5.5), (18.5, -5.5), (-17.5, 3.5), (-7.5, 3.5), (2.5, 3.5), (12.5, 3.5), (-5.5, 13.5),
        (4.5, 13.5), (14.5, 13.5), (0.5, 22.5), (18.5, 22.5),
    ]

    // MARK: Draw

    static func draw(_ ctx: inout GraphicsContext, in size: CGSize, frame f: Double) {
        let scale = min(size.width / artboard.width, size.height / artboard.height)
        ctx.translateBy(x: (size.width - artboard.width * scale) / 2, y: (size.height - artboard.height * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)

        drawBeams(&ctx, f)
        drawOrganizer(&ctx, f)
        for a in 0..<3 { drawAgent(&ctx, f, a) }
        for a in 0..<3 { drawPacket(&ctx, f, a) }
    }

    /// Draws `body` in a layer moved to `at`, scaled and faded as a group.
    static func group(_ ctx: inout GraphicsContext, at: CGPoint, scale: Double = 1, scaleY: Double? = nil, opacity: Double = 1,
                      _ body: (inout GraphicsContext) -> Void) {
        guard opacity > 0.001 else { return }
        ctx.drawLayer { layer in
            layer.opacity = opacity
            layer.translateBy(x: at.x, y: at.y)
            layer.scaleBy(x: scale, y: scaleY ?? scale)
            body(&layer)
        }
    }

    static func roundedRect(_ ctx: inout GraphicsContext, center: CGPoint = .zero, w: Double, h: Double, r: Double, fill: Color? = nil,
                            stroke: Color? = nil, line: Double = 2) {
        let path = Path(roundedRect: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h), cornerRadius: r, style: .continuous)
        if let fill { ctx.fill(path, with: .color(fill)) }
        if let stroke { ctx.stroke(path, with: .color(stroke), lineWidth: line) }
    }

    // MARK: Beams (organizer → agents), drawn on then faded

    static func drawBeams(_ ctx: inout GraphicsContext, _ f: Double) {
        let opacity = f < 130 ? 1 : ramp(f, 130, 170, 1, 0)
        guard f < 175 else { return }
        let ends: [(CGPoint, CGPoint, CGPoint, Double)] = [
            (CGPoint(x: 180, y: 280), CGPoint(x: 70, y: 270), CGPoint(x: 70, y: 348), 40),
            (CGPoint(x: 180, y: 276), CGPoint(x: 180, y: 276), CGPoint(x: 180, y: 348), 50),
            (CGPoint(x: 180, y: 280), CGPoint(x: 290, y: 270), CGPoint(x: 290, y: 348), 60),
        ]
        ctx.drawLayer { layer in
            layer.opacity = opacity
            for (c1, c2, end, s) in ends {
                var path = Path()
                path.move(to: CGPoint(x: 180, y: 204))
                path.addCurve(to: end, control1: c1, control2: c2)
                let trim = ramp(f, s, s + 40)
                guard trim > 0.001 else { continue }
                layer.stroke(path.trimmedPath(from: 0, to: trim), with: .color(accent.opacity(0.5)),
                             style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    // MARK: Organizer: QR, then the dashboard

    static func drawOrganizer(_ ctx: inout GraphicsContext, _ f: Double) {
        let breath = f < 28 ? ramp(f, 0, 28) : (f < 60 ? 1 - ramp(f, 28, 60) : 0)
        let bump = f < 480 ? 0 : (f < 494 ? ramp(f, 480, 494) : (f < 520 ? 1 - ramp(f, 494, 520) : 0))
        let qrOpacity = f < 405 ? 1 : (f < 425 ? 1 - ramp(f, 405, 425) : (f < 505 ? 0 : (f < 535 ? ramp(f, 505, 535) : 1)))
        let dashOpacity = f < 410 ? 0 : (f < 435 ? ramp(f, 410, 435) : (f < 500 ? 1 : (f < 525 ? 1 - ramp(f, 500, 525) : 0)))

        group(&ctx, at: organizer, scale: 1 + 0.04 * breath + 0.05 * bump) { g in
            roundedRect(&g, w: 104, h: 168, r: 22, fill: phone, stroke: phoneLine)
            group(&g, at: .zero, opacity: qrOpacity) { qr in drawQR(&qr) }
            group(&g, at: .zero, opacity: dashOpacity) { dash in drawDashboard(&dash, f) }
        }
    }

    static func drawQR(_ ctx: inout GraphicsContext) {
        for (cx, cy) in [(-19.0, -19.0), (19.0, -19.0), (-19.0, 19.0)] {
            roundedRect(&ctx, center: CGPoint(x: cx, y: cy), w: 18, h: 18, r: 4, stroke: ink, line: 3.5)
            roundedRect(&ctx, center: CGPoint(x: cx, y: cy), w: 6, h: 6, r: 1.5, fill: accent)
        }
        var dots = Path()
        for (x, y) in qrDots { dots.addRect(CGRect(x: x, y: y, width: 5, height: 5)) }
        ctx.fill(dots, with: .color(ink))
    }

    static func drawDashboard(_ ctx: inout GraphicsContext, _ f: Double) {
        let center = CGPoint(x: 0, y: -30)
        let circle = Path(ellipseIn: CGRect(x: center.x - 25, y: center.y - 25, width: 50, height: 50))
        ctx.stroke(circle, with: .color(phoneLine), lineWidth: 6)

        let ring = f < 529 ? ramp(f, 425, 480) : 0
        if ring > 0.001 {
            var arc = Path()
            arc.addArc(center: center, radius: 25, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * ring), clockwise: false)
            ctx.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }

        let check = f < 529 ? ramp(f, 478, 498) : 0
        if check > 0.001 {
            var path = Path()
            path.move(to: CGPoint(x: -9, y: -30))
            path.addLine(to: CGPoint(x: -3, y: -24))
            path.addLine(to: CGPoint(x: 9, y: -37))
            ctx.stroke(path.trimmedPath(from: 0, to: check), with: .color(green),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        let bars: [(Double, Double, Color, Double)] = [(-26, 30, gray, 430), (0, 46, teal, 436), (26, 24, green, 442)]
        for (x, h, color, s) in bars {
            let grown = f < 529 ? ramp(f, s, s + 32) * h : 0
            guard grown > 0.5 else { continue }
            let rect = CGRect(x: x - 7, y: 58 - grown, width: 14, height: grown)
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(4, grown / 2), style: .continuous), with: .color(color))
        }
    }

    // MARK: Agents: phone, rows, visitors

    static func drawAgent(_ ctx: inout GraphicsContext, _ f: Double, _ a: Int) {
        let pop = 70 + 10.0 * Double(a)
        let exit = 505 + 5.0 * Double(a)
        let scaleEnd = [535.0, 538, 540][a], fadeEnd = [530.0, 534, 540][a]
        let scale = f < exit ? ramp(f, pop, pop + 24, 0.6, 1) : ramp(f, exit, scaleEnd, 1, 0.6)
        let opacity = f < exit ? ramp(f, pop, pop + 20) : ramp(f, exit, fadeEnd, 1, 0)
        let send = 340 + 10.0 * Double(a)

        group(&ctx, at: CGPoint(x: agentX[a], y: agentY), scale: scale, opacity: opacity) { g in
            roundedRect(&g, w: 72, h: 124, r: 16, fill: phone, stroke: phoneLine)
            for v in 0..<3 {
                let s = firstVisitor[a] + 50 * Double(v)
                drawRow(&g, f, color: visitorColors[a][v], y: rowY[v], appears: s + 44, send: send)
                drawVisitor(&g, f, color: visitorColors[a][v], x0: visitorX[v], target: rowY[v], start: s)
            }
        }
    }

    static func drawRow(_ ctx: inout GraphicsContext, _ f: Double, color: Color, y: Double, appears t: Double, send: Double) {
        let opacity = f < t ? 0 : (f < t + 12 ? ramp(f, t, t + 12) : (f < send ? 1 : ramp(f, send, send + 12, 1, 0)))
        let sx = f < send ? ramp(f, t, t + 14, 0.4, 1) : ramp(f, send, send + 12, 1, 0.6)
        guard opacity > 0.001 else { return }
        group(&ctx, at: CGPoint(x: 0, y: y), scale: sx, scaleY: 1, opacity: opacity) { g in
            roundedRect(&g, w: 46, h: 11, r: 5.5, fill: color)
        }
    }

    static func drawVisitor(_ ctx: inout GraphicsContext, _ f: Double, color: Color, x0: Double, target: Double, start s: Double) {
        guard f >= s, f < s + 46 else { return }
        let opacity = f < s + 26 ? ramp(f, s, s + 14) : ramp(f, s + 26, s + 46, 1, 0)
        let scale = f < s + 26 ? ramp(f, s, s + 14, 0.4, 1) : ramp(f, s + 26, s + 46, 1, 0.35)
        let move = ramp(f, s + 26, s + 46)
        let at = CGPoint(x: x0 * (1 - move), y: -104 + (target + 104) * move)
        group(&ctx, at: at, scale: scale, opacity: opacity) { g in
            g.fill(Path(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18)), with: .color(color))
        }
    }

    // MARK: Packets: an agent's encrypted file travelling to the organizer

    static func drawPacket(_ ctx: inout GraphicsContext, _ f: Double, _ a: Int) {
        let t = 340 + 10.0 * Double(a)
        guard f >= t, f < t + 56 else { return }
        let opacity = f < t + 44 ? ramp(f, t, t + 10) : ramp(f, t + 44, t + 56, 1, 0)
        let scale = f < t + 30 ? ramp(f, t, t + 10, 0.5, 1) : ramp(f, t + 30, t + 56, 1, 0.35)
        let move = ramp(f, t + 4, t + 54)
        let at = CGPoint(x: agentX[a] + (180 - agentX[a]) * move, y: agentY + (150 - agentY) * move)

        group(&ctx, at: at, scale: scale, opacity: opacity) { g in
            roundedRect(&g, w: 28, h: 28, r: 9, fill: accent)
            roundedRect(&g, center: CGPoint(x: 0, y: 3), w: 11, h: 8, r: 2, fill: .white)
            var shackle = Path()
            shackle.move(to: CGPoint(x: -3.2, y: -1))
            shackle.addLine(to: CGPoint(x: -3.2, y: -3.5))
            shackle.addCurve(to: CGPoint(x: 3.2, y: -3.5), control1: CGPoint(x: -3.2, y: -8), control2: CGPoint(x: 3.2, y: -8))
            shackle.addLine(to: CGPoint(x: 3.2, y: -1))
            g.stroke(shackle, with: .color(.white), lineWidth: 2)
        }
    }
}
