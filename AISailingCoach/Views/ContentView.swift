//
//  ContentView.swift
//  AISailingCoach
//
//  Main application view with instrument panel and AI coach interface
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: SailingViewModel
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Clean dark background
                Color.black
                    .ignoresSafeArea()

                // Main content - no scrolling, fits screen
                VStack(spacing: 0) {
                    // Instrument Panel with new layout
                    InstrumentPanelView(
                        sailingData: viewModel.sailingData,
                        isCoachActive: viewModel.isPushToTalkActive,
                        coachState: viewModel.coachState,
                        onCoachToggle: { viewModel.toggleLiveSession() },
                        visualCoachRecommendations: viewModel.visualCoachRecommendations
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                // Coach message overlay
                if !viewModel.coachMessage.isEmpty {
                    CoachMessageOverlay(message: viewModel.coachMessage)
                }

                // Settings button (top-right)
                VStack {
                    HStack {
                        Spacer()
                        SettingsButton(showSettings: $showSettings)
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.trailing, 16)
            }
        }
        .onAppear {
            viewModel.startSimulator()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Instrument Panel View

struct InstrumentPanelView: View {
    let sailingData: SailingData
    let isCoachActive: Bool
    let coachState: CoachState
    let onCoachToggle: () -> Void

    // Visual coach recommendations (from Gemini 3)
    var visualCoachRecommendations: CoachRecommendations?

    var body: some View {
        VStack(spacing: 10) {
            // Compass Rose
            CompassRoseView(
                courseOverGround: sailingData.courseOverGround,
                trueWindAngle: sailingData.trueWindAngle,
                apparentWindAngle: sailingData.apparentWindAngle,
                trueWindSpeed: sailingData.trueWindSpeed
            )

            // AI Coach Button - centered between compass and panes
            CoachButtonView(
                isActive: isCoachActive,
                coachState: coachState,
                onToggle: onCoachToggle,
                showLabel: false
            )
            .frame(maxWidth: .infinity)

            // Speed Data Boxes (Boat Speed & Target)
            DataBoxesView(
                boatSpeed: sailingData.boatSpeed,
                targetSpeed: sailingData.targetSpeed
            )

            // AI Coach Instruction Panes (Performance, Headsail, Steering, Sail Trim)
            CoachInstructionPanesView(
                performance: sailingData.performance,
                apparentWindAngle: sailingData.apparentWindAngle,
                trueWindAngle: sailingData.trueWindAngle,
                recommendations: visualCoachRecommendations
            )
        }
    }
}

// MARK: - Settings Button

struct SettingsButton: View {
    @Binding var showSettings: Bool

    var body: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}

// MARK: - Coach Message Overlay

struct CoachMessageOverlay: View {
    let message: String
    @State private var isVisible = true

    var body: some View {
        VStack {
            Spacer()

            if isVisible {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(.spatialYellow)

                    Text(message)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .background(.black.opacity(0.9))
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.spatialYellow.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SailingViewModel())
}

#Preview("Instrument Panel Only") {
    InstrumentPanelView(
        sailingData: .upwindSample,
        isCoachActive: false,
        coachState: .idle,
        onCoachToggle: {}
    )
    .background(Color.black)
}
