//
//  SignalKSimulator.swift
//  AISailingCoach
//
//  Simulates a Signal K server providing realistic sailing data
//  for development and testing without a real boat connection
//

import Foundation
import Combine

/// Simulates realistic sailing telemetry data
class SignalKSimulator: ObservableObject {
    // MARK: - Published Properties

    @Published var currentData: SailingData = .empty
    @Published var isRunning: Bool = false

    // MARK: - Private Properties

    private var timer: Timer?
    private var scenario: SimulationScenario = .upwind
    private var elapsedTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 0.5 // 2 Hz update rate

    // Noise and variation parameters
    private var windShiftPhase: Double = 0
    private var gustPhase: Double = 0
    private var wavePhase: Double = 0

    // MARK: - Scenario Base Values

    private struct ScenarioParams {
        let baseCOG: Double
        let baseTWA: Double
        let baseTWS: Double
        let baseBoatSpeed: Double
        let baseTargetSpeed: Double
        let description: String
    }

    private var scenarioParams: ScenarioParams {
        switch scenario {
        case .upwind:
            return ScenarioParams(
                baseCOG: 45,
                baseTWA: 42,
                baseTWS: 12.5,
                baseBoatSpeed: 6.8,
                baseTargetSpeed: 7.5,
                description: "Close-hauled upwind"
            )
        case .downwind:
            return ScenarioParams(
                baseCOG: 180,
                baseTWA: 150,
                baseTWS: 8.0,
                baseBoatSpeed: 5.8,
                baseTargetSpeed: 7.0,
                description: "Broad reach/running"
            )
        case .reaching:
            return ScenarioParams(
                baseCOG: 90,
                baseTWA: 90,
                baseTWS: 15.0,
                baseBoatSpeed: 8.5,
                baseTargetSpeed: 8.2,
                description: "Beam reach"
            )
        case .raceStart:
            return ScenarioParams(
                baseCOG: 0,
                baseTWA: 45,
                baseTWS: 10.0,
                baseBoatSpeed: 4.0,
                baseTargetSpeed: 6.5,
                description: "Pre-start maneuvering"
            )
        case .windShift:
            return ScenarioParams(
                baseCOG: 45,
                baseTWA: 42,
                baseTWS: 12.0,
                baseBoatSpeed: 6.5,
                baseTargetSpeed: 7.2,
                description: "Progressive wind shift"
            )
        case .gust:
            return ScenarioParams(
                baseCOG: 60,
                baseTWA: 50,
                baseTWS: 14.0,
                baseBoatSpeed: 7.0,
                baseTargetSpeed: 7.8,
                description: "Gusty conditions"
            )
        }
    }

    // MARK: - Public Methods

    func start(scenario: SimulationScenario = .upwind) {
        self.scenario = scenario
        elapsedTime = 0
        windShiftPhase = Double.random(in: 0...(.pi * 2))
        gustPhase = Double.random(in: 0...(.pi * 2))
        wavePhase = Double.random(in: 0...(.pi * 2))

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateData()
        }
        isRunning = true

        // Initial update
        updateData()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func setScenario(_ newScenario: SimulationScenario) {
        scenario = newScenario
        // Reset phases for new scenario behavior
        windShiftPhase = Double.random(in: 0...(.pi * 2))
    }

    // MARK: - Private Methods

    private func updateData() {
        elapsedTime += updateInterval

        let params = scenarioParams
        var data = SailingData()

        // Apply scenario-specific variations
        switch scenario {
        case .upwind, .downwind, .reaching:
            data = generateStandardData(params: params)

        case .raceStart:
            data = generateRaceStartData(params: params)

        case .windShift:
            data = generateWindShiftData(params: params)

        case .gust:
            data = generateGustyData(params: params)
        }

        // Calculate apparent wind from true wind and boat motion
        let awaResult = calculateApparentWind(
            tws: data.trueWindSpeed,
            twa: data.trueWindAngle,
            boatSpeed: data.boatSpeed
        )
        data.apparentWindSpeed = awaResult.aws
        data.apparentWindAngle = awaResult.awa

        // Set timestamp
        data.timestamp = Date()

        // Update published data
        DispatchQueue.main.async {
            self.currentData = data
        }
    }

    private func generateStandardData(params: ScenarioParams) -> SailingData {
        // Natural variations using sine waves
        let windNoise = sin(windShiftPhase + elapsedTime * 0.1) * 3  // ±3° wind shift
        let speedNoise = sin(wavePhase + elapsedTime * 0.3) * 0.3   // ±0.3 kts speed variation
        let gustNoise = sin(gustPhase + elapsedTime * 0.5) * 1.0    // ±1 kts gust variation

        return SailingData(
            courseOverGround: normalizeAngle(params.baseCOG + windNoise * 0.5),
            speedOverGround: max(0, params.baseBoatSpeed + speedNoise - 0.2),
            boatSpeed: max(0, params.baseBoatSpeed + speedNoise),
            trueWindSpeed: max(0, params.baseTWS + gustNoise),
            trueWindAngle: params.baseTWA + windNoise,
            apparentWindSpeed: 0, // Calculated later
            apparentWindAngle: 0, // Calculated later
            trueWindDirection: normalizeAngle(params.baseCOG - params.baseTWA),
            targetSpeed: params.baseTargetSpeed
        )
    }

    private func generateRaceStartData(params: ScenarioParams) -> SailingData {
        // Simulate pre-start maneuvering with course changes
        let timeInSequence = elapsedTime.truncatingRemainder(dividingBy: 30)
        let maneuverPhase = timeInSequence / 30.0

        // Boat turns through different angles during maneuvering
        let courseVariation = sin(maneuverPhase * .pi * 4) * 45

        // Speed varies with maneuvering
        let speedFactor = 0.5 + 0.5 * abs(cos(maneuverPhase * .pi * 4))

        return SailingData(
            courseOverGround: normalizeAngle(params.baseCOG + courseVariation),
            speedOverGround: params.baseBoatSpeed * speedFactor * 0.9,
            boatSpeed: params.baseBoatSpeed * speedFactor,
            trueWindSpeed: params.baseTWS + sin(elapsedTime * 0.2) * 1.5,
            trueWindAngle: params.baseTWA + courseVariation,
            apparentWindSpeed: 0,
            apparentWindAngle: 0,
            trueWindDirection: 0,
            targetSpeed: params.baseTargetSpeed
        )
    }

    private func generateWindShiftData(params: ScenarioParams) -> SailingData {
        // Progressive wind shift over time
        let shiftAmount = sin(elapsedTime * 0.05) * 15 // ±15° progressive shift
        let newTWA = params.baseTWA + shiftAmount

        // Boat tries to optimize angle (simplified)
        let cogAdjustment = shiftAmount * 0.8

        return SailingData(
            courseOverGround: normalizeAngle(params.baseCOG + cogAdjustment),
            speedOverGround: params.baseBoatSpeed - abs(shiftAmount) * 0.02,
            boatSpeed: params.baseBoatSpeed - abs(shiftAmount) * 0.02,
            trueWindSpeed: params.baseTWS + sin(elapsedTime * 0.3) * 1.0,
            trueWindAngle: newTWA,
            apparentWindSpeed: 0,
            apparentWindAngle: 0,
            trueWindDirection: normalizeAngle(-shiftAmount),
            targetSpeed: params.baseTargetSpeed
        )
    }

    private func generateGustyData(params: ScenarioParams) -> SailingData {
        // Simulate gusts with varying intensity
        let gustCycle = elapsedTime.truncatingRemainder(dividingBy: 12) // 12 second gust cycle
        let gustIntensity: Double

        if gustCycle < 3 {
            // Building gust
            gustIntensity = gustCycle / 3.0
        } else if gustCycle < 6 {
            // Peak gust
            gustIntensity = 1.0
        } else if gustCycle < 9 {
            // Dying gust
            gustIntensity = 1.0 - (gustCycle - 6) / 3.0
        } else {
            // Lull
            gustIntensity = 0.0
        }

        let gustEffect = gustIntensity * 6.0 // Up to +6 kts in gusts
        let speedBoost = gustIntensity * 1.5 // Boat speeds up in gusts

        return SailingData(
            courseOverGround: params.baseCOG + sin(elapsedTime * 0.2) * 2,
            speedOverGround: params.baseBoatSpeed + speedBoost - 0.2,
            boatSpeed: params.baseBoatSpeed + speedBoost,
            trueWindSpeed: params.baseTWS + gustEffect,
            trueWindAngle: params.baseTWA - gustIntensity * 3, // Wind frees in gusts
            apparentWindSpeed: 0,
            apparentWindAngle: 0,
            trueWindDirection: 0,
            targetSpeed: params.baseTargetSpeed + gustIntensity * 0.5
        )
    }

    // MARK: - Calculations

    private func calculateApparentWind(
        tws: Double,
        twa: Double,
        boatSpeed: Double
    ) -> (aws: Double, awa: Double) {
        // Convert to radians
        let twaRad = twa * .pi / 180

        // True wind components (relative to boat heading)
        // X = perpendicular to boat (positive = wind from port pushing to starboard)
        // Y = along boat centerline (positive = wind from ahead pushing aft)
        let twsX = tws * sin(twaRad)   // Lateral component
        let twsY = tws * cos(twaRad)   // Forward component

        // Apparent wind = true wind + headwind from boat motion
        // Boat moving forward creates apparent wind from ahead,
        // which ADDS to the forward wind component
        let awsX = twsX
        let awsY = twsY + boatSpeed  // ADD boat speed (headwind effect)

        // Calculate apparent wind speed and angle
        let aws = sqrt(awsX * awsX + awsY * awsY)
        var awa = atan2(awsX, awsY) * 180 / .pi

        // Normalize to positive angle
        if awa < 0 {
            awa += 360
        }

        // AWA should now be smaller than TWA (wind shifts forward due to boat motion)
        return (aws: aws, awa: awa)
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        return normalized
    }
}

// MARK: - Signal K WebSocket Client (for real server connection)

class SignalKClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var currentData: SailingData = .empty
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var messageCount = 0

    func connect(to url: URL) {
        print("🔌 SignalKClient: Connecting to \(url)")
        connectionState = .connecting

        // Create session that allows self-signed certificates (for local development)
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        connectionState = .connected
        print("✅ SignalKClient: WebSocket connected, waiting for messages...")
        receiveMessage()
    }

    // MARK: - URLSessionWebSocketDelegate

    // Allow self-signed certificates for local Signal K servers
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // For local development, trust self-signed certificates
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            print("🔐 SignalKClient: Accepting self-signed certificate for \(challenge.protectionSpace.host)")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("✅ SignalKClient: WebSocket opened with protocol: \(`protocol` ?? "none")")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 SignalKClient: WebSocket closed with code: \(closeCode)")
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }

    func disconnect() {
        print("🔌 SignalKClient: Disconnecting")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessage()

            case .failure(let error):
                print("❌ SignalKClient: WebSocket error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.connectionState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ message: String) {
        messageCount += 1

        // Log first few messages and then periodically
        if messageCount <= 3 || messageCount % 100 == 0 {
            print("📨 SignalKClient: Message #\(messageCount): \(message.prefix(200))...")
        }

        // Signal K sends different message types - skip non-delta messages
        // Hello message starts with {"name":...}
        // Delta messages have "updates" array
        guard message.contains("\"updates\"") else {
            if messageCount <= 3 {
                print("⏭️ SignalKClient: Skipping non-delta message")
            }
            return
        }

        guard let delta = SignalKParser.parse(json: message) else {
            print("❌ SignalKClient: Failed to parse delta message")
            return
        }

        DispatchQueue.main.async {
            self.currentData = SignalKParser.parse(delta: delta, into: self.currentData)

            // Log periodically to show current values
            if self.messageCount % 50 == 0 {
                print("⛵ SignalK Data: speed=\(String(format: "%.1f", self.currentData.boatSpeed))kts, AWS=\(String(format: "%.1f", self.currentData.apparentWindSpeed))kts, AWA=\(String(format: "%.0f", self.currentData.apparentWindAngle))°, TWS=\(String(format: "%.1f", self.currentData.trueWindSpeed))kts, TWA=\(String(format: "%.0f", self.currentData.trueWindAngle))°")
            }
        }
    }
}
