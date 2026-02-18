//
//  SailingViewModel.swift
//  AISailingCoach
//
//  Main view model managing sailing data state and services
//

import Foundation
import Combine
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

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

    // MARK: - Visual Coach

    /// Visual coach recommendations for the 4 instruction panes
    @Published var visualCoachRecommendations: CoachRecommendations?

    /// Whether the visual coach is active (defaults to true, persisted in UserDefaults)
    @Published var isVisualCoachActive: Bool = UserDefaults.standard.object(forKey: "VisualCoachEnabled") as? Bool ?? true

    /// Whether using real Signal K server (vs simulator) - persisted in UserDefaults
    @Published var useRealSignalK: Bool = UserDefaults.standard.bool(forKey: "UseRealSignalK")

    /// Currently selected visual coach AI provider (persisted in UserDefaults)
    @Published var visualCoachProvider: VisualCoachProvider = {
        let raw = UserDefaults.standard.string(forKey: UserDefaults.Keys.visualCoachProvider) ?? "gemini"
        return VisualCoachProvider(rawValue: raw) ?? .gemini
    }()

    /// Non-nil when a provider switch was rejected (e.g. Apple Intelligence unavailable).
    /// SettingsView observes this to show an alert.
    @Published var visualCoachProviderError: String?

    /// Whether Apple Foundation Models is available on this device/OS.
    /// Exposed so SettingsView doesn't need to import FoundationModels directly.
    var isAppleProviderAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// Human-readable reason why Apple provider is not available (empty when available).
    var appleProviderUnavailableReason: String {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return "Requires iOS 26 or later" }
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Enable Apple Intelligence in Settings > Apple Intelligence & Siri"
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading — please wait"
        case .unavailable:
            return "Apple Intelligence is not available"
        }
        #else
        return "Requires iOS 26 or later"
        #endif
    }

    // MARK: - Services

    private var signalKSimulator: SignalKSimulator?
    private var signalKClient: SignalKClient?
    private var geminiCoachService: GeminiCoachService?

    // Visual coach services
    private var geminiVisualCoachService: Gemini3VisualCoachService?
    private var _appleCoachService: Any?  // Holds AppleFoundationCoachService on iOS 26+
    private var currentVisualCoachService: (any VisualCoachService)?

    // Dedicated cancellable for the active visual coach — nil'd when switching providers
    private var visualCoachCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - iOS 26 Accessor

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private var appleCoachService: AppleFoundationCoachService? {
        get { _appleCoachService as? AppleFoundationCoachService }
        set { _appleCoachService = newValue }
    }
    #endif

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

        // Initialize Gemini Voice Coach Service
        geminiCoachService = GeminiCoachService()

        geminiCoachService?.getSailingData = { [weak self] in
            self?.buildCoachContext() ?? CoachContext(
                boatSpeed: 0, targetSpeed: 0, performance: 0,
                trueWindSpeed: 0, trueWindAngle: 0, apparentWindAngle: 0,
                courseOverGround: 0, pointOfSail: "Unknown"
            )
        }

        geminiCoachService?.$currentResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                if !response.isEmpty { self?.coachMessage = response }
            }
            .store(in: &cancellables)

        geminiCoachService?.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.coachState = state }
            .store(in: &cancellables)

        geminiCoachService?.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected { self?.connectionStatus = .connected }
            }
            .store(in: &cancellables)

        // Initialize Gemini Visual Coach
        geminiVisualCoachService = Gemini3VisualCoachService()

        // Initialize Apple Foundation Coach (iOS 26+ only)
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            appleCoachService = AppleFoundationCoachService()
        }
        #endif

        // Activate the persisted provider
        activateProvider(visualCoachProvider)

        // Initialize Signal K Client for real server connection
        signalKClient = SignalKClient()

        signalKClient?.$currentData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self = self, self.useRealSignalK else { return }
                self.sailingData = data
                if data.apparentWindSpeed > 0 || data.trueWindSpeed > 0 {
                    print("📱 ViewModel received SignalK: AWS=\(String(format: "%.1f", data.apparentWindSpeed))kts, TWS=\(String(format: "%.1f", data.trueWindSpeed))kts")
                }
            }
            .store(in: &cancellables)

        // Auto-connect to Signal K server if previously enabled
        if useRealSignalK {
            if let savedURL = UserDefaults.standard.string(forKey: "SignalKServerURL"), !savedURL.isEmpty {
                print("🔄 Auto-reconnecting to Signal K server: \(savedURL)")
                Task { @MainActor in self.connectToSignalK(url: savedURL) }
            } else {
                useRealSignalK = false
                UserDefaults.standard.set(false, forKey: "UseRealSignalK")
            }
        }
    }

    // MARK: - Visual Coach Provider Switching

    /// Switch the active visual coach provider. Shows an error and does nothing if
    /// the requested provider is not available on this device.
    func setVisualCoachProvider(_ provider: VisualCoachProvider) {
        guard provider != visualCoachProvider else { return }

        if provider == .apple {
            #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                if case .available = SystemLanguageModel.default.availability {
                    // Available — proceed
                } else {
                    visualCoachProviderError = appleProviderUnavailableReason
                    return
                }
            } else {
                visualCoachProviderError = "Apple Foundation Models requires iOS 26 or later."
                return
            }
            #else
            visualCoachProviderError = "Apple Foundation Models requires iOS 26 or later."
            return
            #endif
        }

        visualCoachProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: UserDefaults.Keys.visualCoachProvider)
        activateProvider(provider)
    }

    /// Internal: stop current service, subscribe to new one, start if coach is enabled.
    private func activateProvider(_ provider: VisualCoachProvider) {
        // Stop whatever is running and drop the Combine subscription
        currentVisualCoachService?.stop()
        visualCoachCancellable = nil

        let service: (any VisualCoachService)?

        switch provider {
        case .gemini:
            geminiVisualCoachService?.getSailingData = { [weak self] in self?.sailingData ?? .empty }
            service = geminiVisualCoachService

        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                appleCoachService?.getSailingData = { [weak self] in self?.sailingData ?? .empty }
                service = appleCoachService
            } else {
                // Fall back to Gemini silently on older OS
                geminiVisualCoachService?.getSailingData = { [weak self] in self?.sailingData ?? .empty }
                service = geminiVisualCoachService
            }
            #else
            geminiVisualCoachService?.getSailingData = { [weak self] in self?.sailingData ?? .empty }
            service = geminiVisualCoachService
            #endif
        }

        currentVisualCoachService = service

        // Re-subscribe
        visualCoachCancellable = service?.recommendationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recommendations in
                self?.visualCoachRecommendations = recommendations
            }

        if isVisualCoachActive {
            service?.start()
        }
    }

    // MARK: - Signal K Server Connection

    func connectToSignalK(url: String) {
        UserDefaults.standard.set(url, forKey: "SignalKServerURL")

        guard let serverURL = URL(string: url) else {
            print("❌ Invalid Signal K URL: \(url)")
            connectionStatus = .error
            return
        }

        print("🔌 Connecting to Signal K server: \(url)")
        connectionStatus = .connecting

        if isSimulatorRunning {
            signalKSimulator?.stop()
            isSimulatorRunning = false
        }

        signalKClient?.connect(to: serverURL)
        useRealSignalK = true
        UserDefaults.standard.set(true, forKey: "UseRealSignalK")
        connectionStatus = .connected

        if isVisualCoachActive {
            currentVisualCoachService?.start()
        }
    }

    func disconnectSignalK() {
        print("🔌 Disconnecting from Signal K server")
        signalKClient?.disconnect()
        useRealSignalK = false
        UserDefaults.standard.set(false, forKey: "UseRealSignalK")
        connectionStatus = .disconnected
    }

    // MARK: - Simulator Control

    func startSimulator() {
        signalKSimulator?.start(scenario: simulationScenario)
        isSimulatorRunning = true
        connectionStatus = .connected

        if isVisualCoachActive {
            print("🎯 Auto-starting visual coach with simulator")
            currentVisualCoachService?.start()
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
            print("⏹️ Stopping session")
            isPushToTalkActive = false
            coachState = .idle
            geminiCoachService?.endLiveSession()
        } else {
            print("▶️ Starting session")
            isPushToTalkActive = true
            let context = buildCoachContext()
            Task { await geminiCoachService?.startLiveSession(context: context) }
        }
    }

    func sendCoachQuery(_ query: String) {
        Task { await geminiCoachService?.sendTextMessage(query) }
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
            currentVisualCoachService?.stop()
            isVisualCoachActive = false
            UserDefaults.standard.set(false, forKey: "VisualCoachEnabled")
        } else {
            print("▶️ Starting visual coach")
            currentVisualCoachService?.start()
            isVisualCoachActive = true
            UserDefaults.standard.set(true, forKey: "VisualCoachEnabled")
        }
    }

    // MARK: - Configuration

    func configureGeminiAPI(key: String) {
        geminiCoachService?.configure(apiKey: key)
        geminiVisualCoachService?.configure(apiKey: key)
        // Apple Foundation Coach needs no API key — no-op for apple provider
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
