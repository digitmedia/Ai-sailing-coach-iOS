//
//  SettingsView.swift
//  AISailingCoach
//
//  App settings including API configuration, simulator controls, and preferences
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SailingViewModel
    @Environment(\.dismiss) var dismiss

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var selectedScenario: SimulationScenario = .upwind
    @State private var signalKURL: String = "ws://localhost:3000/signalk/v1/stream?subscribe=all"
    @State private var showProviderAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // AI Coach Configuration
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("Gemini API Key", text: $apiKey)
                                .textContentType(.password)
                                .autocapitalization(.none)
                        } else {
                            SecureField("Gemini API Key", text: $apiKey)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Save API Key") {
                        viewModel.configureGeminiAPI(key: apiKey)
                    }
                    .disabled(apiKey.isEmpty)

                    Link("Get Gemini API Key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                } header: {
                    Text("AI Coach")
                } footer: {
                    Text("Your API key is stored locally on your device.")
                }

                // Visual Coach
                Section {
                    Toggle("Visual Coach Active", isOn: Binding(
                        get: { viewModel.isVisualCoachActive },
                        set: { _ in viewModel.toggleVisualCoach() }
                    ))

                    if viewModel.isVisualCoachActive {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Updating every 10 seconds")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Visual Coach", systemImage: "gauge.with.needle")
                } footer: {
                    Text(visualCoachFooter)
                }

                // Visual Coach AI Provider
                Section {
                    Picker("Visual Coach AI", selection: Binding(
                        get: { viewModel.visualCoachProvider },
                        set: { viewModel.setVisualCoachProvider($0) }
                    )) {
                        Text("Gemini 3 Flash").tag(VisualCoachProvider.gemini)
                        Text("Apple Foundation Models").tag(VisualCoachProvider.apple)
                            .disabled(!viewModel.isAppleProviderAvailable)
                    }

                    if !viewModel.isAppleProviderAvailable {
                        Label(viewModel.appleProviderUnavailableReason, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if viewModel.visualCoachProvider == .apple {
                        Label("On-device — no API key or network required", systemImage: "cpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI Model")
                } footer: {
                    Text(appleProviderFooter)
                }
                .alert("Provider Unavailable", isPresented: $showProviderAlert) {
                    Button("OK") { viewModel.visualCoachProviderError = nil }
                } message: {
                    Text(viewModel.visualCoachProviderError ?? "")
                }
                .onChange(of: viewModel.visualCoachProviderError) { _, error in
                    showProviderAlert = error != nil
                }

                // Simulator Settings
                Section {
                    Toggle("Simulator Active", isOn: Binding(
                        get: { viewModel.isSimulatorRunning },
                        set: { newValue in
                            if newValue {
                                viewModel.startSimulator()
                            } else {
                                viewModel.stopSimulator()
                            }
                        }
                    ))

                    Picker("Scenario", selection: $selectedScenario) {
                        ForEach(SimulationScenario.allCases) { scenario in
                            VStack(alignment: .leading) {
                                Text(scenario.rawValue)
                            }
                            .tag(scenario)
                        }
                    }
                    .onChange(of: selectedScenario) { _, newScenario in
                        viewModel.setScenario(newScenario)
                    }
                } header: {
                    Text("Signal K Simulator")
                } footer: {
                    Text(selectedScenario.description)
                }

                // Connection Settings (for real Signal K server)
                Section {
                    TextField("Signal K Server URL", text: $signalKURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .textContentType(.URL)

                    Toggle("Use Signal K Server", isOn: Binding(
                        get: { viewModel.useRealSignalK },
                        set: { newValue in
                            if newValue {
                                viewModel.connectToSignalK(url: signalKURL)
                            } else {
                                viewModel.disconnectSignalK()
                            }
                        }
                    ))

                    HStack {
                        Circle()
                            .fill(viewModel.connectionStatus == .connected ? Color.laylineGreen : Color.performanceRed)
                            .frame(width: 10, height: 10)
                        Text(viewModel.connectionStatus.rawValue)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Signal K Server")
                } footer: {
                    Text("Connect to a real Signal K server for live boat data. Default: ws://localhost:3000/signalk/v1/stream?subscribe=all")
                }

                // Display Settings
                Section {
                    Toggle("High Contrast Mode", isOn: .constant(false))
                    Toggle("Night Mode (Red)", isOn: .constant(false))

                    Picker("Update Rate", selection: .constant(2)) {
                        Text("1 Hz").tag(1)
                        Text("2 Hz").tag(2)
                        Text("5 Hz").tag(5)
                    }
                } header: {
                    Text("Display")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2026.02.01")
                            .foregroundColor(.secondary)
                    }

                    Link("Spatial Sail Website", destination: URL(string: "https://spatialsail.app")!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Load saved API key
            if let savedKey = UserDefaults.standard.string(forKey: "GeminiAPIKey") {
                apiKey = savedKey
            }
            // Load saved Signal K URL
            if let savedURL = UserDefaults.standard.string(forKey: "SignalKServerURL") {
                signalKURL = savedURL
            }
            selectedScenario = viewModel.simulationScenario
        }
    }

    // MARK: - Computed Properties

    private var visualCoachFooter: String {
        switch viewModel.visualCoachProvider {
        case .gemini:
            return "Visual Coach uses Gemini 3 Flash to provide real-time sailing recommendations in the instruction panes."
        case .apple:
            return "Visual Coach uses Apple Foundation Models (on-device) to provide real-time sailing recommendations."
        }
    }

    private var appleProviderFooter: String {
        if viewModel.isAppleProviderAvailable {
            return "Apple Foundation Models runs fully on-device — private, free, and works without a network connection. Gemini 3 Flash uses the cloud and requires an API key."
        }
        return "Apple Foundation Models requires iOS 26 or later with Apple Intelligence enabled. Gemini 3 Flash works on all supported devices."
    }
}

// MARK: - Scenario Detail View

struct ScenarioDetailView: View {
    let scenario: SimulationScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scenario.rawValue)
                .font(.headline)

            Text(scenario.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Debug Section (Development Only)

#if DEBUG
struct DebugSettingsSection: View {
    @EnvironmentObject var viewModel: SailingViewModel

    var body: some View {
        Section {
            Button("Load Upwind Sample") {
                // Direct data injection for testing
            }

            Button("Load Downwind Sample") {
                // Direct data injection for testing
            }

            Button("Simulate Wind Shift") {
                viewModel.setScenario(.windShift)
            }

            Button("Simulate Gust") {
                viewModel.setScenario(.gust)
            }
        } header: {
            Text("Debug")
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(SailingViewModel())
}
