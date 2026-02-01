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

                // LLM Provider Selection
                Section {
                    Picker("AI Provider", selection: .constant("gemini")) {
                        Text("Gemini Live API").tag("gemini")
                        Text("Apple Foundation Models").tag("apple")
                            .disabled(true)
                    }
                } header: {
                    Text("AI Model")
                } footer: {
                    Text("Apple Foundation Models support coming in a future update.")
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
                    TextField("Signal K Server URL", text: .constant(""))
                        .disabled(true)
                        .foregroundColor(.secondary)

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
                    Text("Connect to a real Signal K server for live boat data. Currently using simulator.")
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

                    Link("Spatial Sail Website", destination: URL(string: "https://spatialsail.com")!)
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
            selectedScenario = viewModel.simulationScenario
        }
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
