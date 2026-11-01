//
// MeshlineSplashView.swift
// Meshline
//
// Animated launch splash drawn from the app icon motif: mesh nodes pop in,
// links draw between them, the orange center pulses, then the wordmark fades
// in. It is a passive overlay: the app underneath starts immediately and
// touches pass through, so it never delays startup or onboarding.
//

import SwiftUI

struct MeshlineSplashView: View {
    static let navy = Color(red: 10 / 255, green: 41 / 255, blue: 91 / 255)
    static let teal = Color(red: 64 / 255, green: 224 / 255, blue: 208 / 255)
    static let node = Color(red: 38 / 255, green: 196 / 255, blue: 150 / 255)
    static let orange = Color(red: 1, green: 170 / 255, blue: 60 / 255)

    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nodesShown = false
    @State private var linkProgress: CGFloat = 0
    @State private var pulse = false
    @State private var wordmarkShown = false
    @State private var dismissing = false

    /// Outer hexagon nodes, unit coordinates, clockwise from the top.
    private static let outer: [CGPoint] = (0..<6).map { i in
        let a = (-90.0 + Double(i) * 60.0) * .pi / 180
        return CGPoint(x: cos(a), y: sin(a))
    }

    var body: some View {
        ZStack {
            Self.navy.ignoresSafeArea()
            VStack(spacing: 28) {
                mesh.frame(width: 150, height: 150)
                Text(verbatim: "Meshline")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(wordmarkShown ? 1 : 0)
                    .offset(y: wordmarkShown || reduceMotion ? 0 : 8)
            }
        }
        .opacity(dismissing ? 0 : 1)
        .scaleEffect(dismissing && !reduceMotion ? 1.08 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: run)
    }

    private var mesh: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2 - 12
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let pts = Self.outer.map { CGPoint(x: c.x + $0.x * r, y: c.y + $0.y * r) }
            ZStack {
                Path { p in
                    for i in 0..<6 {
                        p.move(to: c); p.addLine(to: pts[i])
                        p.move(to: pts[i]); p.addLine(to: pts[(i + 1) % 6])
                    }
                }
                .trim(from: 0, to: linkProgress)
                .stroke(Self.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .shadow(color: Self.teal.opacity(0.8), radius: 6)

                ForEach(0..<6, id: \.self) { i in
                    Circle().fill(Self.node)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .frame(width: 20, height: 20)
                        .position(pts[i])
                        .scaleEffect(nodesShown ? 1 : 0.01, anchor: .center)
                        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55).delay(Double(i) * 0.05), value: nodesShown)
                }
                Circle().fill(Self.orange.opacity(0.35))
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulse ? 1.9 : 1)
                    .opacity(pulse ? 0 : 1)
                    .position(c)
                Circle().fill(Self.orange)
                    .overlay(Circle().stroke(Color.white, lineWidth: 4))
                    .frame(width: 32, height: 32)
                    .scaleEffect(nodesShown ? (pulse ? 1.12 : 1) : 0.01)
                    .position(c)
            }
        }
    }

    private func run() {
        if reduceMotion {
            nodesShown = true; linkProgress = 1; wordmarkShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) { dismissing = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: onFinished)
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { nodesShown = true }
        withAnimation(.easeInOut(duration: 0.5).delay(0.25)) { linkProgress = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { pulse = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.8)) { wordmarkShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeIn(duration: 0.25)) { dismissing = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: onFinished)
    }
}

