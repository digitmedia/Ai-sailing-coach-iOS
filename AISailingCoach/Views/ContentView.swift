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

                // Main content
                VStack(spacing: 16) {
                    // Top spacer for status bar
                    Spacer()
                        .frame(height: 20)

                    // Instrument Panel - fills available space
                    InstrumentPanelView(
                        sailingData: viewModel.sailingData
                    )
                    .padding(.horizontal, 16)

                    Spacer()
                        .frame(minHeight: 20, maxHeight: 40)

                    // AI Coach Button - tap to start/stop live session
                    CoachButtonView(
                        isActive: viewModel.isPushToTalkActive,
                        coachState: viewModel.coachState,
                        onToggle: { viewModel.toggleLiveSession() }
                    )
                    .padding(.bottom, 24)
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

    var body: some View {
        // Bezel effect container
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Compass Rose
                CompassRoseView(
                    courseOverGround: sailingData.courseOverGround,
                    trueWindAngle: sailingData.trueWindAngle,
                    apparentWindAngle: sailingData.apparentWindAngle,
                    trueWindSpeed: sailingData.trueWindSpeed
                )

                // Speed Data Boxes
                DataBoxesView(
                    boatSpeed: sailingData.boatSpeed,
                    targetSpeed: sailingData.targetSpeed
                )
            }
            .padding(16)
            .background(LinearGradient.panelBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
        }
        .padding(8)
        .background(LinearGradient.bezelBackground)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
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
                .padding(.bottom, 120)
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
    InstrumentPanelView(sailingData: .upwindSample)
        .padding()
        .background(Color.black)
}
