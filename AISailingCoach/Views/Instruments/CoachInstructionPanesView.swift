//
//  CoachInstructionPanesView.swift
//  AISailingCoach
//
//  AI Coach instruction panes for visual sailing guidance
//  These panes will be connected to the AI API in a future version
//

import SwiftUI

// MARK: - Instruction Types

enum HeadsailType: String, CaseIterable {
    case genoa = "Genoa"
    case code0 = "Code 0"
    case gennaker = "Gennaker"
}

enum SteeringAction: String, CaseIterable {
    case steady = "Steady"
    case headUp = "Head Up"
    case bearAway = "Bear Away"
}

enum SailTrimAction: String, CaseIterable {
    case hold = "Hold"
    case sheetIn = "Sheet In"
    case ease = "Ease"
}

// MARK: - Coach Instruction Panes Grid

struct CoachInstructionPanesView: View {
    let performance: Int
    let apparentWindAngle: Double
    let trueWindAngle: Double

    // AI Coach recommendations (from Gemini 3 Visual Coach)
    var recommendations: CoachRecommendations?

    // Computed properties with fallback to local calculation
    private var currentHeadsail: HeadsailType {
        if let rec = recommendations {
            return rec.recommendedHeadsail.asHeadsailType
        }
        // Fallback: calculate from TWA
        return HeadsailRecommendation.fromWindAngle(trueWindAngle).asHeadsailType
    }

    private var currentSteering: SteeringAction {
        recommendations?.steeringRecommendation.asSteeringAction ?? .steady
    }

    private var currentSailTrim: SailTrimAction {
        recommendations?.sailTrimRecommendation.asSailTrimAction ?? .hold
    }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            // Row 1: Performance & Headsail
            MiniPerformancePane(performance: performance)
            HeadsailPane(currentSail: currentHeadsail)

            // Row 2: Steering & Sail Trim
            SteeringPane(
                currentAction: currentSteering,
                apparentWindAngle: apparentWindAngle
            )
            SailTrimPane(currentAction: currentSailTrim)
        }
    }
}

// MARK: - Mini Performance Pane

struct MiniPerformancePane: View {
    let performance: Int

    private let startAngle: Double = 135
    private let endAngle: Double = 405
    private var totalAngle: Double { endAngle - startAngle }

    private var progressAngle: Double {
        startAngle + (totalAngle * min(Double(performance), 100) / 100)
    }

    private var performanceColor: Color {
        performance >= 85 ? .spatialYellow : .performanceRed
    }

    var body: some View {
        InstructionPaneContainer(label: "PERFORMANCE") {
            GeometryReader { geometry in
                let size = geometry.size
                let centerX = size.width / 2
                let centerY = size.height / 2
                let radius = min(size.width, size.height) / 2 - 10
                let strokeWidth: CGFloat = 8

                ZStack {
                    // Background arc
                    ArcShape(startAngle: startAngle, endAngle: endAngle)
                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

                    // Progress arc
                    ArcShape(startAngle: startAngle, endAngle: progressAngle)
                        .stroke(performanceColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .shadow(color: performanceColor.opacity(0.5), radius: 4)

                    // Center percentage - positioned inside the arc
                    Text("\(performance)%")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: 12, y: 0)
                }
            }
            .frame(height: 65)
        }
    }
}

// MARK: - Arc Shape Helper

struct ArcShape: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 10

        return Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startAngle - 90),
                endAngle: .degrees(endAngle - 90),
                clockwise: false
            )
        }
    }
}

// MARK: - Headsail Pane

struct HeadsailPane: View {
    let currentSail: HeadsailType

    var body: some View {
        InstructionPaneContainer(label: "HEADSAIL") {
            VStack(spacing: 4) {
                // Sail icon
                sailIcon
                    .frame(height: 50)

                Text(currentSail.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sailIcon: some View {
        switch currentSail {
        case .genoa:
            // Triangular genoa sail shape
            GenoaSailShape()
                .fill(Color.white.opacity(0.2))
                .overlay(GenoaSailShape().stroke(Color.white, lineWidth: 2))
                .frame(width: 40, height: 50)
        case .code0:
            // Code 0 sail with panel lines
            Code0SailView()
                .frame(width: 38, height: 50)
        case .gennaker:
            // Gennaker sail with panel lines
            GennakerSailView()
                .frame(width: 42, height: 50)
        }
    }
}

// MARK: - Sail Shape Helpers

struct GenoaSailShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Code 0 Sail View (with panel lines)

struct Code0SailView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Sail outline path - asymmetric reaching sail
            var outline = Path()
            outline.move(to: CGPoint(x: w * 0.5, y: 0))  // Head (top)

            // Curved luff (leading edge)
            outline.addQuadCurve(
                to: CGPoint(x: w * 0.15, y: h),  // Tack (bottom left)
                control: CGPoint(x: w * 0.1, y: h * 0.5)
            )

            // Foot (bottom edge)
            outline.addLine(to: CGPoint(x: w * 0.5, y: h * 0.95))  // Clew area

            // Curved leech (trailing edge)
            outline.addQuadCurve(
                to: CGPoint(x: w * 0.5, y: 0),  // Back to head
                control: CGPoint(x: w * 0.95, y: h * 0.4)
            )

            // Draw filled outline
            context.fill(outline, with: .color(.white.opacity(0.15)))
            context.stroke(outline, with: .color(.white), lineWidth: 2)

            // Draw radial panel lines from tack
            let tackPoint = CGPoint(x: w * 0.15, y: h)
            let numLines = 12

            for i in 0..<numLines {
                let t = Double(i) / Double(numLines - 1)
                // Interpolate along the leech curve
                let endX = w * 0.5 + (w * 0.45 - w * 0.5) * sin(t * .pi * 0.8)
                let endY = t * h * 0.9

                var line = Path()
                line.move(to: tackPoint)
                line.addLine(to: CGPoint(x: endX, y: endY))
                context.stroke(line, with: .color(.white.opacity(0.6)), lineWidth: 1)
            }

            // Horizontal battens
            for i in 1...4 {
                let y = h * Double(i) / 5.0
                var batten = Path()
                batten.move(to: CGPoint(x: w * 0.2, y: y))
                batten.addLine(to: CGPoint(x: w * 0.7, y: y * 0.9))
                context.stroke(batten, with: .color(.white.opacity(0.4)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Gennaker Sail View (with panel lines)

struct GennakerSailView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Sail outline path - full symmetric spinnaker shape
            var outline = Path()
            outline.move(to: CGPoint(x: w * 0.5, y: 0))  // Head (top center)

            // Left side curve (luff)
            outline.addQuadCurve(
                to: CGPoint(x: w * 0.1, y: h * 0.85),  // Left clew
                control: CGPoint(x: w * 0.05, y: h * 0.4)
            )

            // Bottom curve
            outline.addQuadCurve(
                to: CGPoint(x: w * 0.9, y: h * 0.85),  // Right clew
                control: CGPoint(x: w * 0.5, y: h * 1.1)
            )

            // Right side curve (leech)
            outline.addQuadCurve(
                to: CGPoint(x: w * 0.5, y: 0),  // Back to head
                control: CGPoint(x: w * 0.95, y: h * 0.4)
            )

            // Draw filled outline
            context.fill(outline, with: .color(.white.opacity(0.15)))
            context.stroke(outline, with: .color(.white), lineWidth: 2)

            // Draw radial panel lines from head
            let headPoint = CGPoint(x: w * 0.5, y: 0)
            let numLines = 10

            for i in 0..<numLines {
                let t = Double(i) / Double(numLines - 1)
                let angle = -0.4 * .pi + t * 0.8 * .pi  // Spread from left to right
                let length = h * 0.8
                let endX = headPoint.x + cos(angle + .pi / 2) * length * 0.8
                let endY = headPoint.y + sin(angle + .pi / 2) * length

                var line = Path()
                line.move(to: headPoint)
                line.addLine(to: CGPoint(x: endX, y: endY))
                context.stroke(line, with: .color(.white.opacity(0.6)), lineWidth: 1)
            }

            // Draw radial lines from both clews
            let leftClew = CGPoint(x: w * 0.1, y: h * 0.85)
            let rightClew = CGPoint(x: w * 0.9, y: h * 0.85)

            for i in 0..<5 {
                let t = Double(i) / 4.0
                // Lines from left clew
                var leftLine = Path()
                leftLine.move(to: leftClew)
                leftLine.addLine(to: CGPoint(x: w * 0.3 + t * w * 0.2, y: h * 0.3 + t * h * 0.3))
                context.stroke(leftLine, with: .color(.white.opacity(0.4)), lineWidth: 1)

                // Lines from right clew
                var rightLine = Path()
                rightLine.move(to: rightClew)
                rightLine.addLine(to: CGPoint(x: w * 0.7 - t * w * 0.2, y: h * 0.3 + t * h * 0.3))
                context.stroke(rightLine, with: .color(.white.opacity(0.4)), lineWidth: 1)
            }

            // Horizontal seams
            for i in 1...3 {
                let y = h * Double(i) / 4.5
                let xOffset = w * 0.15 * (1 - Double(i) / 4.0)
                var seam = Path()
                seam.move(to: CGPoint(x: xOffset + w * 0.1, y: y))
                seam.addLine(to: CGPoint(x: w * 0.9 - xOffset, y: y))
                context.stroke(seam, with: .color(.white.opacity(0.3)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Steering Pane

struct SteeringPane: View {
    let currentAction: SteeringAction
    let apparentWindAngle: Double

    // Wind direction determines arrow direction
    // Wind from right (positive AWA): head up = right, bear away = left
    // Wind from left (negative AWA): head up = left, bear away = right
    private var windFromRight: Bool {
        apparentWindAngle >= 0
    }

    var body: some View {
        InstructionPaneContainer(label: "STEERING") {
            VStack(spacing: 4) {
                // Direction icon
                steeringIcon
                    .font(.system(size: 40))
                    .foregroundColor(.white)

                Text(currentAction.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var steeringIcon: some View {
        switch currentAction {
        case .steady:
            Image(systemName: "arrow.up.circle")
        case .headUp:
            Image(systemName: windFromRight ? "arrow.right" : "arrow.left")
        case .bearAway:
            Image(systemName: windFromRight ? "arrow.left" : "arrow.right")
        }
    }
}

// MARK: - Sail Trim Pane

struct SailTrimPane: View {
    let currentAction: SailTrimAction

    var body: some View {
        InstructionPaneContainer(label: "SAIL TRIM") {
            VStack(spacing: 4) {
                // Action icon
                trimIcon
                    .font(.system(size: 40))
                    .foregroundColor(.white)

                Text(currentAction.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var trimIcon: some View {
        switch currentAction {
        case .hold:
            Image(systemName: "lock.fill")
        case .sheetIn:
            VStack(spacing: -8) {
                Image(systemName: "arrow.down")
                Text("PULL")
                    .font(.system(size: 8))
                    .opacity(0.6)
            }
        case .ease:
            VStack(spacing: -8) {
                Text("EASE")
                    .font(.system(size: 8))
                    .opacity(0.6)
                Image(systemName: "arrow.up")
            }
        }
    }
}

// MARK: - Instruction Pane Container

struct InstructionPaneContainer<Content: View>: View {
    let label: String
    let content: () -> Content

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.spatialYellow)
                .tracking(1)

            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.spatialYellow, lineWidth: 2)
        )
    }
}

// MARK: - Previews

#Preview("Coach Instruction Panes") {
    CoachInstructionPanesView(
        performance: 85,
        apparentWindAngle: 35,
        trueWindAngle: 42
    )
    .padding()
    .background(Color.black)
}

#Preview("Mini Performance Pane") {
    MiniPerformancePane(performance: 91)
        .frame(width: 180, height: 140)
        .padding()
        .background(Color.black)
}

#Preview("Headsail Panes") {
    HStack(spacing: 12) {
        HeadsailPane(currentSail: .genoa)
        HeadsailPane(currentSail: .code0)
        HeadsailPane(currentSail: .gennaker)
    }
    .frame(height: 140)
    .padding()
    .background(Color.black)
}

#Preview("Steering Panes") {
    HStack(spacing: 12) {
        SteeringPane(currentAction: .steady, apparentWindAngle: 35)
        SteeringPane(currentAction: .headUp, apparentWindAngle: 35)
        SteeringPane(currentAction: .bearAway, apparentWindAngle: 35)
    }
    .frame(height: 140)
    .padding()
    .background(Color.black)
}

#Preview("Sail Trim Panes") {
    HStack(spacing: 12) {
        SailTrimPane(currentAction: .hold)
        SailTrimPane(currentAction: .sheetIn)
        SailTrimPane(currentAction: .ease)
    }
    .frame(height: 140)
    .padding()
    .background(Color.black)
}
