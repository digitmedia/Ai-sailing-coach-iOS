//
//  AppleFoundationCoachService.swift
//  AISailingCoach
//
//  Visual coaching service using Apple Foundation Models (iOS 26+).
//  Provides on-device sailing recommendations with no API key or network connection required.
//
//  Wrapped in #if canImport(FoundationModels) so the project still compiles on
//  Xcode 15 / older SDKs — the Apple provider simply stays unavailable on those builds.
//

import Foundation
import Combine

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@MainActor
class AppleFoundationCoachService: ObservableObject, VisualCoachService {

    // MARK: - Published Properties (VisualCoachService conformance)

    @Published var recommendations: CoachRecommendations?
    @Published var isActive: Bool = false
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    var recommendationsPublisher: AnyPublisher<CoachRecommendations?, Never> {
        $recommendations.eraseToAnyPublisher()
    }

    // MARK: - Configuration

    private let updateInterval: TimeInterval = 10.0
    private var updateTimer: Timer?
    private var session: LanguageModelSession?

    var getSailingData: (() -> SailingData)?

    // MARK: - System Instructions

    private let systemInstructions = """
    You are a sailing performance coach analysing real-time boat telemetry.
    Given boat speed (knots), performance percentage (0-100), and true wind angle (degrees),
    recommend the optimal headsail, steering correction, and sail trim.
    Use only the structured output options — be decisive and consistent.
    Headsail guide: genoa if TWA < 50°, code0 if 50–90°, gennaker if > 90°.
    Steering guide: steady if performance ≥ 95%, bearAway to build speed, headUp if overpowered.
    Trim guide: hold if performance ≥ 95%, sheetIn for 90–95%, ease below 90% to build speed.
    """

    // MARK: - Structured Output Types
    // Private @Generable types map to the shared CoachRecommendations model.

    @Generable
    struct SailingCoachOutput {
        @Guide(description: "Headsail: use genoa for TWA under 50°, code0 for 50-90°, gennaker above 90°")
        var recommendedHeadsail: HeadsailChoice

        @Guide(description: "Steering: steady if performance is 95% or higher, bearAway to build speed, headUp if overpowered")
        var steeringRecommendation: SteeringChoice

        @Guide(description: "Sail trim: hold if 95%+, sheetIn for 90-95%, ease below 90%")
        var sailTrimRecommendation: TrimChoice

        @Generable
        enum HeadsailChoice { case genoa, code0, gennaker }

        @Generable
        enum SteeringChoice { case steady, headUp, bearAway }

        @Generable
        enum TrimChoice { case hold, sheetIn, ease }
    }

    // MARK: - Initialization

    init() {
        createSessionIfAvailable()
    }

    private func createSessionIfAvailable() {
        guard case .available = SystemLanguageModel.default.availability else {
            lastError = describeUnavailability()
            return
        }
        session = LanguageModelSession(instructions: systemInstructions)
    }

    // MARK: - Service Control

    func start() {
        guard !isActive else { return }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable:
            lastError = describeUnavailability()
            print("❌ Apple Coach unavailable: \(lastError ?? "")")
            // Provide local fallback so panes don't go blank
            if let data = getSailingData?() {
                recommendations = CoachRecommendations.calculateFallback(from: data)
            }
            return
        }

        if session == nil {
            session = LanguageModelSession(instructions: systemInstructions)
        }

        print("🍎 Starting Apple Foundation Coach (updates every \(updateInterval)s)")
        isActive = true
        lastError = nil

        Task { await fetchRecommendations() }

        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchRecommendations() }
        }
    }

    func stop() {
        print("🛑 Stopping Apple Foundation Coach")
        updateTimer?.invalidate()
        updateTimer = nil
        isActive = false
        isLoading = false
        // Keep session warm for fast restart
    }

    // MARK: - Inference

    private func fetchRecommendations() async {
        // Guard against concurrent requests (Foundation Models API: one at a time per session)
        guard !isLoading else {
            print("⏭️ Apple Coach: skipping fetch, previous request still in flight")
            return
        }

        guard let getSailingData else {
            lastError = "No sailing data callback configured"
            return
        }

        guard let session else {
            lastError = "Session not initialised — check Apple Intelligence availability"
            return
        }

        let data = getSailingData()
        isLoading = true

        let prompt = """
        Analyse and recommend:
        Speed: \(String(format: "%.1f", data.boatSpeed)) knots
        Performance: \(data.performance)%
        True Wind Angle: \(Int(data.trueWindAngle))°
        """

        print("📊 Apple Coach: speed=\(String(format: "%.1f", data.boatSpeed))kts, perf=\(data.performance)%, TWA=\(Int(data.trueWindAngle))°")

        do {
            let response = try await session.respond(to: prompt, generating: SailingCoachOutput.self)
            let output = response.content
            self.recommendations = mapToRecommendations(output)
            self.lastError = nil
            print("✅ Apple Coach: headsail=\(output.recommendedHeadsail), steering=\(output.steeringRecommendation), trim=\(output.sailTrimRecommendation)")
        } catch {
            print("❌ Apple Coach error: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            self.recommendations = CoachRecommendations.calculateFallback(from: data)
            // Reset session so the next start() gets a fresh one
            self.session = nil
        }

        isLoading = false
    }

    // MARK: - Model Mapping

    private func mapToRecommendations(_ output: SailingCoachOutput) -> CoachRecommendations {
        let headsail: HeadsailRecommendation = switch output.recommendedHeadsail {
        case .genoa: .genoa
        case .code0: .code0
        case .gennaker: .gennaker
        }
        let steering: SteeringRecommendation = switch output.steeringRecommendation {
        case .steady: .steady
        case .headUp: .headUp
        case .bearAway: .bearAway
        }
        let trim: SailTrimRecommendation = switch output.sailTrimRecommendation {
        case .hold: .hold
        case .sheetIn: .sheetIn
        case .ease: .ease
        }
        return CoachRecommendations(
            recommendedHeadsail: headsail,
            steeringRecommendation: steering,
            sailTrimRecommendation: trim
        )
    }

    // MARK: - Availability

    func describeUnavailability() -> String {
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
            return "Apple Intelligence is not available on this device"
        }
    }
}

#endif // canImport(FoundationModels)
