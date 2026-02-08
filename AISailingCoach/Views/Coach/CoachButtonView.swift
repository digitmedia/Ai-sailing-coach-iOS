//
//  CoachButtonView.swift
//  AISailingCoach
//
//  Toggle button for AI sailing coach live session
//  Tap once to start, tap again to stop
//

import SwiftUI

struct CoachButtonView: View {
    let isActive: Bool
    let coachState: CoachState
    let onToggle: () -> Void
    var showLabel: Bool = true

    @State private var pulseAnimation = false
    @State private var waveAnimation = false

    private var buttonColor: Color {
        switch coachState {
        case .idle:
            return .spatialYellow
        case .listening:
            return .spatialTurquoise
        case .processing:
            return .orange
        case .speaking:
            return .laylineGreen
        case .error:
            return .performanceRed
        }
    }

    private var iconName: String {
        switch coachState {
        case .idle:
            return "sparkles"  // Gemini-style sparkle icon
        case .listening:
            return "waveform"
        case .processing:
            return "ellipsis"
        case .speaking:
            return "speaker.wave.2.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusText: String {
        coachState.rawValue
    }

    var body: some View {
        VStack(spacing: 8) {
            // Main button - 20% larger
            ZStack {
                // Outer glow/pulse ring
                Circle()
                    .fill(buttonColor.opacity(0.2))
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.5)

                // Background ring
                Circle()
                    .stroke(buttonColor.opacity(0.3), lineWidth: 2.5)
                    .frame(width: 77, height: 77)

                // Active state ring
                if isActive || coachState != .idle {
                    Circle()
                        .stroke(buttonColor, lineWidth: 2.5)
                        .frame(width: 77, height: 77)
                        .scaleEffect(waveAnimation ? 1.1 : 1.0)
                        .opacity(waveAnimation ? 0 : 1)
                }

                // Button background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                buttonColor.opacity(isActive ? 0.9 : 0.8),
                                buttonColor.opacity(isActive ? 0.7 : 0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: buttonColor.opacity(0.5), radius: isActive ? 14 : 10)

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, value: coachState)
            }
            .frame(width: 96, height: 96)
            .onTapGesture {
                onToggle()
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: isActive)

            // Status label (optional)
            if showLabel {
                Text(statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .onChange(of: coachState) { _, newState in
            if newState == .listening || newState == .processing {
                startAnimations()
            } else if newState == .idle {
                stopAnimations()
            }
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulseAnimation = true
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            waveAnimation = true
        }
    }

    private func stopAnimations() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulseAnimation = false
            waveAnimation = false
        }
    }
}

// MARK: - Audio Waveform Visualization

struct AudioWaveformView: View {
    let isActive: Bool
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 5)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.spatialTurquoise)
                    .frame(width: 4, height: levels[index] * 30)
            }
        }
        .frame(height: 30)
        .onAppear {
            if isActive {
                animateLevels()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                animateLevels()
            } else {
                resetLevels()
            }
        }
    }

    private func animateLevels() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard isActive else {
                timer.invalidate()
                return
            }

            withAnimation(.easeInOut(duration: 0.1)) {
                levels = (0..<5).map { _ in CGFloat.random(in: 0.2...1.0) }
            }
        }
    }

    private func resetLevels() {
        withAnimation(.easeOut(duration: 0.3)) {
            levels = Array(repeating: 0.3, count: 5)
        }
    }
}

// MARK: - Coach Status Indicator

struct CoachStatusIndicator: View {
    let state: CoachState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(state.rawValue)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7))
        .cornerRadius(16)
    }

    private var statusColor: Color {
        switch state {
        case .idle: return .white.opacity(0.5)
        case .listening: return .spatialTurquoise
        case .processing: return .orange
        case .speaking: return .laylineGreen
        case .error: return .performanceRed
        }
    }
}

// MARK: - Previews

#Preview("Idle State") {
    VStack(spacing: 40) {
        CoachButtonView(
            isActive: false,
            coachState: .idle,
            onToggle: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}

#Preview("Listening State") {
    VStack(spacing: 40) {
        CoachButtonView(
            isActive: true,
            coachState: .listening,
            onToggle: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}

#Preview("All States") {
    VStack(spacing: 20) {
        ForEach([CoachState.idle, .listening, .processing, .speaking, .error], id: \.rawValue) { state in
            CoachStatusIndicator(state: state)
        }
    }
    .padding()
    .background(Color.black)
}
