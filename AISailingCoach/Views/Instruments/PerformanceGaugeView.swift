//
//  PerformanceGaugeView.swift
//  AISailingCoach
//
//  Arc gauge showing boat performance as percentage of target polar speed
//

import SwiftUI

struct PerformanceGaugeView: View {
    let performance: Int

    // Gauge configuration
    private let startAngle: Double = 135
    private let endAngle: Double = 405
    private var totalAngle: Double { endAngle - startAngle }

    // Animation state
    @State private var animatedPerformance: Double = 0

    private var progressAngle: Double {
        startAngle + (totalAngle * min(animatedPerformance, 100) / 100)
    }

    private var performanceColor: Color {
        performance >= 85 ? .spatialYellow : .performanceRed
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("PERFORMANCE")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.spatialYellow)
                .tracking(2)

            ZStack {
                // Gauge canvas
                Canvas { context, size in
                    drawGauge(context: context, size: size)
                }
                .frame(height: 192)

                // Center percentage display
                VStack(spacing: 4) {
                    Text("\(performance)%")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .offset(y: 20)
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.spatialYellow, lineWidth: 2)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedPerformance = Double(performance)
            }
        }
        .onChange(of: performance) { _, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedPerformance = Double(newValue)
            }
        }
    }

    // MARK: - Drawing

    private func drawGauge(context: GraphicsContext, size: CGSize) {
        let scale = size.width / 300
        let centerX = size.width / 2
        let centerY: CGFloat = 130 * scale
        let radius: CGFloat = 90 * scale
        let strokeWidth: CGFloat = 20 * scale

        // Background arc
        let backgroundPath = createArcPath(
            start: startAngle,
            end: endAngle,
            center: CGPoint(x: centerX, y: centerY),
            radius: radius
        )
        context.stroke(
            backgroundPath,
            with: .color(.white.opacity(0.1)),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
        )

        // Progress arc with glow
        let progressPath = createArcPath(
            start: startAngle,
            end: progressAngle,
            center: CGPoint(x: centerX, y: centerY),
            radius: radius
        )

        // Draw glow effect (shadow)
        context.stroke(
            progressPath,
            with: .color(performanceColor.opacity(0.3)),
            style: StrokeStyle(lineWidth: strokeWidth + 8, lineCap: .round)
        )
        
        // Draw main progress arc
        context.stroke(
            progressPath,
            with: .color(performanceColor),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
        )

        // Draw tick marks
        drawTickMarks(
            context: context,
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            strokeWidth: strokeWidth
        )

        // Draw percentage labels
        drawPercentageLabels(
            context: context,
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            strokeWidth: strokeWidth,
            scale: scale
        )
    }

    private func createArcPath(
        start: Double,
        end: Double,
        center: CGPoint,
        radius: CGFloat
    ) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(start - 90),
                endAngle: .degrees(end - 90),
                clockwise: false
            )
        }
    }

    private func drawTickMarks(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        strokeWidth: CGFloat
    ) {
        for value in [0, 25, 50, 75, 100] {
            let angle = startAngle + (totalAngle * Double(value) / 100)
            let outerPoint = polarToCartesian(
                angle: angle,
                radius: radius + strokeWidth / 2 + 2,
                center: center
            )
            let innerPoint = polarToCartesian(
                angle: angle,
                radius: radius - strokeWidth / 2 - 5,
                center: center
            )

            var tickPath = Path()
            tickPath.move(to: innerPoint)
            tickPath.addLine(to: outerPoint)

            context.stroke(
                tickPath,
                with: .color(.white.opacity(0.3)),
                lineWidth: 2
            )
        }
    }

    private func drawPercentageLabels(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        strokeWidth: CGFloat,
        scale: CGFloat
    ) {
        let labelRadius = radius + strokeWidth / 2 + 15

        for value in [0, 50, 100] {
            let angle = startAngle + (totalAngle * Double(value) / 100)
            let position = polarToCartesian(
                angle: angle,
                radius: labelRadius,
                center: center
            )

            let text = Text("\(value)")
                .font(.system(size: 10 * scale))
                .foregroundColor(.white.opacity(0.5))

            context.draw(text, at: position)
        }
    }

    private func polarToCartesian(
        angle: Double,
        radius: CGFloat,
        center: CGPoint
    ) -> CGPoint {
        let rad = (angle - 90) * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(rad)),
            y: center.y + radius * CGFloat(sin(rad))
        )
    }
}

// MARK: - Mini Performance Gauge (for compact displays)

struct MiniPerformanceGauge: View {
    let performance: Int

    var body: some View {
        Gauge(value: Double(performance), in: 0...100) {
            Text("PERF")
                .font(.caption2)
        } currentValueLabel: {
            Text("\(performance)%")
                .font(.caption.bold())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(performance >= 85 ? Color.spatialYellow : Color.performanceRed)
    }
}

// MARK: - Previews

#Preview("High Performance") {
    PerformanceGaugeView(performance: 91)
        .frame(width: 380)
        .padding()
        .background(Color.black)
}

#Preview("Low Performance") {
    PerformanceGaugeView(performance: 74)
        .frame(width: 380)
        .padding()
        .background(Color.black)
}

#Preview("Perfect Performance") {
    PerformanceGaugeView(performance: 100)
        .frame(width: 380)
        .padding()
        .background(Color.black)
}

#Preview("Mini Gauge") {
    MiniPerformanceGauge(performance: 85)
        .frame(width: 60, height: 60)
        .padding()
        .background(Color.black)
}
