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

    // AI Coach instructions (placeholders - will be connected to API later)
    var currentHeadsail: HeadsailType = .genoa
    var currentSteering: SteeringAction = .bearAway
    var currentSailTrim: SailTrimAction = .ease

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
            // Curved code 0 shape
            Code0SailShape()
                .fill(Color.white.opacity(0.2))
                .overlay(Code0SailShape().stroke(Color.white, lineWidth: 2))
                .frame(width: 35, height: 50)
        case .gennaker:
            // Rounded gennaker shape
            GennakerSailShape()
                .fill(Color.white.opacity(0.2))
                .overlay(GennakerSailShape().stroke(Color.white, lineWidth: 2))
                .frame(width: 40, height: 50)
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

struct Code0SailShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX - 5, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX - 5, y: rect.maxY),
                control: CGPoint(x: rect.maxX + 10, y: rect.midY)
            )
            path.addLine(to: CGPoint(x: rect.midX - 5, y: rect.minY))
        }
    }
}

struct GennakerSailShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.maxX + 5, y: rect.midY - 10)
            )
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
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
        apparentWindAngle: 35
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
