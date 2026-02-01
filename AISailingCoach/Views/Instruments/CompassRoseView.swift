//
//  CompassRoseView.swift
//  AISailingCoach
//
//  High-performance compass rose with rotating card, wind indicators, and laylines
//  Uses SwiftUI Canvas for optimal rendering performance
//

import SwiftUI

struct CompassRoseView: View {
    let courseOverGround: Double
    let trueWindAngle: Double
    let apparentWindAngle: Double
    let trueWindSpeed: Double

    // Animation state
    @State private var animatedCOG: Double = 0

    // Layline angles (fixed relative to boat)
    private let laylineAnglePort: Double = -45
    private let laylineAngleStarboard: Double = 45

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Main compass canvas
                Canvas { context, canvasSize in
                    let scale = canvasSize.width / 300
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                    // Draw rotating compass card
                    drawCompassCard(
                        context: &context,
                        center: center,
                        scale: scale,
                        rotation: -animatedCOG
                    )

                    // Draw fixed elements (laylines, boat marker)
                    drawFixedElements(
                        context: &context,
                        center: center,
                        scale: scale
                    )

                    // Draw wind indicators
                    drawWindIndicators(
                        context: &context,
                        center: center,
                        scale: scale
                    )
                }
                .frame(width: size, height: size)

                // COG display at top (overlay)
                VStack {
                    COGBadgeView(courseOverGround: courseOverGround)
                    Spacer()
                }
                .frame(width: size, height: size)

                // Center AWA display (overlay)
                AWACenterDisplay(apparentWindAngle: apparentWindAngle)
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            animatedCOG = courseOverGround
        }
        .onChange(of: courseOverGround) { oldValue, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animatedCOG = normalizeAngleTransition(from: oldValue, to: newValue)
            }
        }
    }

    // MARK: - Drawing Functions

    private func drawCompassCard(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        rotation: Double
    ) {
        // Save context state
        var rotatedContext = context

        // Apply rotation around center
        rotatedContext.translateBy(x: center.x, y: center.y)
        rotatedContext.rotate(by: .degrees(rotation))
        rotatedContext.translateBy(x: -center.x, y: -center.y)

        // Draw outer circles
        let outerRadius: CGFloat = 130 * scale
        let yellowRingRadius: CGFloat = 133 * scale

        // White outer circle
        let outerCircle = Path(ellipseIn: CGRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        rotatedContext.stroke(
            outerCircle,
            with: .color(.white.opacity(0.3)),
            lineWidth: 1
        )

        // Yellow accent ring
        let yellowRing = Path(ellipseIn: CGRect(
            x: center.x - yellowRingRadius,
            y: center.y - yellowRingRadius,
            width: yellowRingRadius * 2,
            height: yellowRingRadius * 2
        ))
        rotatedContext.stroke(
            yellowRing,
            with: .color(.spatialYellow),
            lineWidth: 2
        )

        // Draw degree tick marks
        for i in 0..<360 {
            let angle = Double(i)
            let (innerRadius, strokeWidth, opacity) = tickMarkStyle(for: i)

            let scaledInner = innerRadius * scale
            let scaledOuter: CGFloat = 130 * scale

            let rad = angle * .pi / 180
            let x1 = center.x + scaledInner * CGFloat(sin(rad))
            let y1 = center.y - scaledInner * CGFloat(cos(rad))
            let x2 = center.x + scaledOuter * CGFloat(sin(rad))
            let y2 = center.y - scaledOuter * CGFloat(cos(rad))

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x1, y: y1))
            tickPath.addLine(to: CGPoint(x: x2, y: y2))

            rotatedContext.stroke(
                tickPath,
                with: .color(.white.opacity(opacity)),
                lineWidth: strokeWidth
            )
        }

        // Draw cardinal direction labels (counter-rotate to stay readable)
        drawCardinalLabels(
            context: &rotatedContext,
            center: center,
            scale: scale,
            counterRotation: -rotation
        )

        // Draw degree numbers
        drawDegreeLabels(
            context: &rotatedContext,
            center: center,
            scale: scale,
            counterRotation: -rotation
        )
    }

    private func tickMarkStyle(for degree: Int) -> (CGFloat, CGFloat, Double) {
        let isCardinal = degree % 90 == 0
        let isMajor = degree % 30 == 0
        let isMedium = degree % 10 == 0

        if isCardinal {
            return (105, 3, 1.0)
        } else if isMajor {
            return (110, 2, 1.0)
        } else if isMedium {
            return (115, 1, 0.9)
        } else {
            return (122, 0.5, 0.7)
        }
    }

    private func drawCardinalLabels(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        counterRotation: Double
    ) {
        let cardinals: [(String, Double)] = [
            ("N", 0), ("E", 90), ("S", 180), ("W", 270)
        ]
        let radius: CGFloat = 85 * scale

        for (label, angle) in cardinals {
            let rad = angle * .pi / 180
            let x = center.x + radius * CGFloat(sin(rad))
            let y = center.y - radius * CGFloat(cos(rad))

            // Create text with counter-rotation
            var textContext = context
            textContext.translateBy(x: x, y: y)
            textContext.rotate(by: .degrees(counterRotation))
            textContext.translateBy(x: -x, y: -y)

            let text = Text(label)
                .font(.system(size: 20 * scale, weight: .bold))
                .foregroundColor(.white)

            textContext.draw(text, at: CGPoint(x: x, y: y))
        }
    }

    private func drawDegreeLabels(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        counterRotation: Double
    ) {
        let degrees = [30, 60, 120, 150, 210, 240, 300, 330]
        let radius: CGFloat = 95 * scale

        for angle in degrees {
            let rad = Double(angle) * .pi / 180
            let x = center.x + radius * CGFloat(sin(rad))
            let y = center.y - radius * CGFloat(cos(rad))

            var textContext = context
            textContext.translateBy(x: x, y: y)
            textContext.rotate(by: .degrees(counterRotation))
            textContext.translateBy(x: -x, y: -y)

            let text = Text("\(angle)")
                .font(.system(size: 12 * scale))
                .foregroundColor(.white)

            textContext.draw(text, at: CGPoint(x: x, y: y))
        }
    }

    private func drawFixedElements(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat
    ) {
        // Boat heading marker (triangle at top)
        var boatMarker = Path()
        boatMarker.move(to: CGPoint(x: center.x, y: center.y - 140 * scale))
        boatMarker.addLine(to: CGPoint(x: center.x - 5 * scale, y: center.y - 125 * scale))
        boatMarker.addLine(to: CGPoint(x: center.x + 5 * scale, y: center.y - 125 * scale))
        boatMarker.closeSubpath()
        context.fill(boatMarker, with: .color(.white))

        // Port layline (red, dashed)
        drawLayline(
            context: &context,
            center: center,
            scale: scale,
            angle: laylineAnglePort,
            color: .performanceRed
        )

        // Starboard layline (green, dashed)
        drawLayline(
            context: &context,
            center: center,
            scale: scale,
            angle: laylineAngleStarboard,
            color: .laylineGreen
        )
    }

    private func drawLayline(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        angle: Double,
        color: Color
    ) {
        let length: CGFloat = 120 * scale
        let rad = angle * .pi / 180
        let endX = center.x + length * CGFloat(sin(rad))
        let endY = center.y - length * CGFloat(cos(rad))

        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: endX, y: endY))

        context.stroke(
            path,
            with: .color(color.opacity(0.9)),
            style: StrokeStyle(lineWidth: 2, dash: [5, 5])
        )
    }

    private func drawWindIndicators(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat
    ) {
        // True Wind indicator (turquoise) at trueWindAngle
        drawWindTriangle(
            context: &context,
            center: center,
            scale: scale,
            angle: trueWindAngle,
            color: .spatialTurquoise,
            label: "T"
        )

        // Apparent Wind indicator (yellow) at apparentWindAngle
        drawWindTriangle(
            context: &context,
            center: center,
            scale: scale,
            angle: apparentWindAngle,
            color: .spatialYellow,
            label: "A"
        )
    }

    private func drawWindTriangle(
        context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        angle: Double,
        color: Color,
        label: String
    ) {
        let tipRadius: CGFloat = 115 * scale
        let baseRadius: CGFloat = 140 * scale
        let spread: Double = 4

        let rad = angle * .pi / 180
        let leftRad = (angle - spread) * .pi / 180
        let rightRad = (angle + spread) * .pi / 180

        let tipX = center.x + tipRadius * CGFloat(sin(rad))
        let tipY = center.y - tipRadius * CGFloat(cos(rad))
        let leftX = center.x + baseRadius * CGFloat(sin(leftRad))
        let leftY = center.y - baseRadius * CGFloat(cos(leftRad))
        let rightX = center.x + baseRadius * CGFloat(sin(rightRad))
        let rightY = center.y - baseRadius * CGFloat(cos(rightRad))

        var triangle = Path()
        triangle.move(to: CGPoint(x: tipX, y: tipY))
        triangle.addLine(to: CGPoint(x: leftX, y: leftY))
        triangle.addLine(to: CGPoint(x: rightX, y: rightY))
        triangle.closeSubpath()

        context.fill(triangle, with: .color(color.opacity(0.9)))
        context.stroke(triangle, with: .color(.white), lineWidth: 1)

        // Label
        let labelRadius: CGFloat = 131 * scale
        let labelX = center.x + labelRadius * CGFloat(sin(rad))
        let labelY = center.y - labelRadius * CGFloat(cos(rad))

        let text = Text(label)
            .font(.system(size: 10 * scale, weight: .bold))
            .foregroundColor(.white)
        context.draw(text, at: CGPoint(x: labelX, y: labelY))
    }

    // MARK: - Helpers

    private func normalizeAngleTransition(from oldAngle: Double, to newAngle: Double) -> Double {
        let diff = newAngle - oldAngle
        if abs(diff) > 180 {
            return oldAngle + (diff > 0 ? diff - 360 : diff + 360)
        }
        return newAngle
    }
}

// MARK: - COG Badge View

struct COGBadgeView: View {
    let courseOverGround: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("COG")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .tracking(1)

            Text("\(Int(courseOverGround))°")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - AWA Center Display

struct AWACenterDisplay: View {
    let apparentWindAngle: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(abs(apparentWindAngle)))")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)
                Text("°")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)

            Text("AWA")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .tracking(2)
        }
    }
}

// MARK: - Preview

#Preview("Upwind") {
    CompassRoseView(
        courseOverGround: 45,
        trueWindAngle: 42,
        apparentWindAngle: 35,
        trueWindSpeed: 12.5
    )
    .frame(width: 350, height: 350)
    .background(Color.black)
}

#Preview("Reaching") {
    CompassRoseView(
        courseOverGround: 90,
        trueWindAngle: 90,
        apparentWindAngle: 75,
        trueWindSpeed: 15.0
    )
    .frame(width: 350, height: 350)
    .background(Color.black)
}

#Preview("Downwind") {
    CompassRoseView(
        courseOverGround: 180,
        trueWindAngle: 150,
        apparentWindAngle: 140,
        trueWindSpeed: 8.0
    )
    .frame(width: 350, height: 350)
    .background(Color.black)
}
