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

    // MARK: - Visual Coach (Gemini 3)

    /// Visual coach recommendations for the 4 instruction panes
    @Published var visualCoachRecommendations: CoachRecommendations?

    /// Whether the visual coach is active (defaults to true, persisted in UserDefaults)
    @Published var isVisualCoachActive: Bool = UserDefaults.standard.object(forKey: "VisualCoachEnabled") as? Bool ?? true

    // MARK: - Services

    private var signalKSimulator: SignalKSimulator?
    private var geminiCoachService: GeminiCoachService?
    private var visualCoachService: Gemini3VisualCoachService?
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

        // Setup callback for periodic data updates
        geminiCoachService?.getSailingData = { [weak self] in
            self?.buildCoachContext() ?? CoachContext(
                boatSpeed: 0, targetSpeed: 0, performance: 0,
                trueWindSpeed: 0, trueWindAngle: 0, apparentWindAngle: 0,
                courseOverGround: 0, pointOfSail: "Unknown"
            )
        }

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

        geminiCoachService?.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected {
                    self?.connectionStatus = .connected
                }
            }
            .store(in: &cancellables)

        // Initialize Gemini 3 Visual Coach Service
        visualCoachService = Gemini3VisualCoachService()

        // Setup callback to get sailing data
        visualCoachService?.getSailingData = { [weak self] in
            self?.sailingData ?? .empty
        }

        // Subscribe to visual coach recommendations
        visualCoachService?.$recommendations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recommendations in
                self?.visualCoachRecommendations = recommendations
            }
            .store(in: &cancellables)

        // Note: isVisualCoachActive is managed via UserDefaults, not synced from service
        // This allows the setting to persist and show correctly on app launch
    }

    // MARK: - Simulator Control

    func startSimulator() {
        signalKSimulator?.start(scenario: simulationScenario)
        isSimulatorRunning = true
        connectionStatus = .connected

        // Auto-start visual coach when simulator starts (if enabled in settings)
        if isVisualCoachActive {
            print("🎯 Auto-starting visual coach with simulator")
            visualCoachService?.start()
        }
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

    func toggleLiveSession() {
        print("🔄 Toggle called. Currently active: \(isPushToTalkActive), state: \(coachState)")

        if isPushToTalkActive || coachState != .idle {
            // Stop the session
            print("⏹️ Stopping session")
            isPushToTalkActive = false
            coachState = .idle
            geminiCoachService?.endLiveSession()
        } else {
            // Start the session
            print("▶️ Starting session")
            isPushToTalkActive = true
            let context = buildCoachContext()
            Task {
                await geminiCoachService?.startLiveSession(context: context)
            }
        }
    }

    func sendCoachQuery(_ query: String) {
        Task {
            await geminiCoachService?.sendTextMessage(query)
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

    // MARK: - Visual Coach Control

    func toggleVisualCoach() {
        if isVisualCoachActive {
            print("🛑 Stopping visual coach")
            visualCoachService?.stop()
            isVisualCoachActive = false
            UserDefaults.standard.set(false, forKey: "VisualCoachEnabled")
        } else {
            print("▶️ Starting visual coach")
            visualCoachService?.start()
            isVisualCoachActive = true
            UserDefaults.standard.set(true, forKey: "VisualCoachEnabled")
        }
    }

    // MARK: - Configuration

    func configureGeminiAPI(key: String) {
        geminiCoachService?.configure(apiKey: key)
        visualCoachService?.configure(apiKey: key)
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
    case idle = "Ask Coach"
    case listening = "Listening..."
    case processing = "Thinking..."
    case speaking = "Speaking..."
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
