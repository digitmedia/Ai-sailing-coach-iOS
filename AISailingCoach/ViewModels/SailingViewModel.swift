//
//  SailingViewModel.swift
//  AISailingCoach
//
//  Main view model managing sailing data state and services
//

import Foundation
import Combine
import SwiftUI

@MainActor
class SailingViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Current sailing data from Signal K
    @Published var sailingData: SailingData = .upwindSample

    /// Whether the Signal K simulator is running
    @Published var isSimulatorRunning: Bool = false

    /// Current simulation scenario
    @Published var simulationScenario: SimulationScenario = .upwind

    /// AI Coach state
    @Published var coachState: CoachState = .idle

    /// Latest coach message
    @Published var coachMessage: String = ""

    /// Whether push-to-talk is active
    @Published var isPushToTalkActive: Bool = false

    /// Connection status
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Services

    private var signalKSimulator: SignalKSimulator?
    private var geminiCoachService: GeminiCoachService?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupServices()
    }

    private func setupServices() {
        // Initialize Signal K Simulator
        signalKSimulator = SignalKSimulator()

        // Subscribe to simulator data
        signalKSimulator?.$currentData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.sailingData = data
            }
            .store(in: &cancellables)

        // Initialize Gemini Coach Service
        geminiCoachService = GeminiCoachService()

        // Subscribe to coach responses
        geminiCoachService?.$currentResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                if !response.isEmpty {
                    self?.coachMessage = response
                }
            }
            .store(in: &cancellables)

        geminiCoachService?.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.coachState = state
            }
            .store(in: &cancellables)
    }

    // MARK: - Simulator Control

    func startSimulator() {
        signalKSimulator?.start(scenario: simulationScenario)
        isSimulatorRunning = true
        connectionStatus = .connected
    }

    func stopSimulator() {
        signalKSimulator?.stop()
        isSimulatorRunning = false
        connectionStatus = .disconnected
    }

    func setScenario(_ scenario: SimulationScenario) {
        simulationScenario = scenario
        signalKSimulator?.setScenario(scenario)
    }

    // MARK: - AI Coach Control

    func startPushToTalk() {
        isPushToTalkActive = true
        coachState = .listening
        geminiCoachService?.startListening(context: buildCoachContext())
    }

    func stopPushToTalk() {
        isPushToTalkActive = false
        geminiCoachService?.stopListening()
    }

    func sendCoachQuery(_ query: String) {
        let context = buildCoachContext()
        Task {
            await geminiCoachService?.sendQuery(query, context: context)
        }
    }

    private func buildCoachContext() -> CoachContext {
        CoachContext(
            boatSpeed: sailingData.boatSpeed,
            targetSpeed: sailingData.targetSpeed,
            performance: sailingData.performance,
            trueWindSpeed: sailingData.trueWindSpeed,
            trueWindAngle: sailingData.trueWindAngle,
            apparentWindAngle: sailingData.apparentWindAngle,
            courseOverGround: sailingData.courseOverGround,
            pointOfSail: sailingData.pointOfSail.rawValue
        )
    }

    // MARK: - Configuration

    func configureGeminiAPI(key: String) {
        geminiCoachService?.configure(apiKey: key)
    }
}

// MARK: - Supporting Types

enum ConnectionStatus: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"
}

enum CoachState: String {
    case idle = "Ready"
    case listening = "Listening..."
    case processing = "Processing..."
    case speaking = "Coach speaking..."
    case error = "Error"
}

enum SimulationScenario: String, CaseIterable, Identifiable {
    case upwind = "Upwind"
    case downwind = "Downwind"
    case reaching = "Reaching"
    case raceStart = "Race Start"
    case windShift = "Wind Shift"
    case gust = "Gust Response"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .upwind:
            return "Close-hauled sailing with good VMG"
        case .downwind:
            return "Running/broad reach with spinnaker"
        case .reaching:
            return "Beam reach at maximum speed"
        case .raceStart:
            return "Pre-start maneuvering sequence"
        case .windShift:
            return "Progressive wind shift scenario"
        case .gust:
            return "Gust and lull variations"
        }
    }
}

/// Context sent to AI coach for relevant advice
struct CoachContext: Codable {
    let boatSpeed: Double
    let targetSpeed: Double
    let performance: Int
    let trueWindSpeed: Double
    let trueWindAngle: Double
    let apparentWindAngle: Double
    let courseOverGround: Double
    let pointOfSail: String

    var description: String {
        """
        Current sailing conditions:
        - Point of sail: \(pointOfSail)
        - Boat speed: \(String(format: "%.1f", boatSpeed)) kts (target: \(String(format: "%.1f", targetSpeed)) kts)
        - Performance: \(performance)%
        - True wind: \(String(format: "%.1f", trueWindSpeed)) kts at \(Int(trueWindAngle))°
        - Apparent wind angle: \(Int(apparentWindAngle))°
        - Course over ground: \(Int(courseOverGround))°
        """
    }
}
