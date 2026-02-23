//
//  SpeechService.swift
//  AISailingCoach
//
//  Handles speech recognition and text-to-speech for AI coaching
//  Uses iOS Speech framework and AVFoundation
//

import Foundation
import Speech
import AVFoundation

/// Service for speech recognition and synthesis
class SpeechService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var isSpeaking = false
    @Published var isAvailable = false

    // MARK: - Private Properties

    // Speech Recognition
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var hasTap = false

    // Text-to-Speech
    private let synthesizer = AVSpeechSynthesizer()

    // Audio Player for Gemini audio responses
    private var audioPlayer: AVAudioPlayer?

    // Callback for transcription results
    private var onTranscription: ((String?) -> Void)?
    private var speakContinuation: CheckedContinuation<Void, Never>?

    // Check if running in simulator
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Initialization

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        synthesizer.delegate = self

        // Don't auto-request permissions - let UI trigger this
        checkAvailability()
    }

    // MARK: - Availability Check

    private func checkAvailability() {
        // Speech recognition may not work well on simulator
        if isSimulator {
            print("⚠️ Running on simulator - speech features may be limited")
            isAvailable = false
            return
        }

        isAvailable = speechRecognizer?.isAvailable ?? false
    }

    // MARK: - Permissions

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        var speechAuthorized = false
        var micAuthorized = false

        let group = DispatchGroup()

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechAuthorized = (status == .authorized)
            print("Speech recognition: \(status == .authorized ? "authorized" : "denied")")
            group.leave()
        }

        group.enter()
        AVAudioApplication.requestRecordPermission { granted in
            micAuthorized = granted
            print("Microphone: \(granted ? "granted" : "denied")")
            group.leave()
        }

        group.notify(queue: .main) {
            self.isAvailable = speechAuthorized && micAuthorized && !self.isSimulator
            completion(self.isAvailable)
        }
    }

    // MARK: - Speech Recognition

    private var hasSimulatedOnce = false

    func startListening(onTranscription: @escaping (String?) -> Void) {
        self.onTranscription = onTranscription

        // Check if available
        guard !isSimulator else {
            print("⚠️ Speech recognition not available on simulator")
            // Simulate a response for testing (only once per session)
            guard !hasSimulatedOnce else {
                print("Already simulated once, waiting for real input")
                return
            }
            hasSimulatedOnce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                onTranscription("How can I improve my VMG?")
            }
            return
        }

        // Stop any existing recognition
        stopListening()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session error: \(error.localizedDescription)")
            onTranscription(nil)
            return
        }

        // Create fresh audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ Failed to create audio engine")
            onTranscription(nil)
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Failed to create recognition request")
            onTranscription(nil)
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                let transcription = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = transcription
                }
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                DispatchQueue.main.async {
                    if isFinal, let text = result?.bestTranscription.formattedString {
                        self.onTranscription?(text)
                    }
                    self.stopListening()
                }
            }
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Check for valid format
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("❌ Invalid audio format - sampleRate: \(recordingFormat.sampleRate), channels: \(recordingFormat.channelCount)")
            onTranscription(nil)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        hasTap = true

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
            }
        } catch {
            print("❌ Audio engine start error: \(error.localizedDescription)")
            cleanupAudio()
            onTranscription(nil)
        }
    }

    func stopListening() {
        cleanupAudio()

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        hasSimulatedOnce = false  // Reset for next session

        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    private func cleanupAudio() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
        }
        audioEngine = nil
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.isSpeaking = true

                // Configure audio session for playback
                let audioSession = AVAudioSession.sharedInstance()
                try? audioSession.setCategory(.playback, mode: .default, options: [])
                try? audioSession.setActive(true)

                // Create utterance
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
                utterance.pitchMultiplier = 1.0
                utterance.volume = 1.0

                // Store continuation for delegate callback
                self.speakContinuation = continuation

                self.synthesizer.speak(utterance)
            }
        }
    }

    // MARK: - Audio Playback

    private var audioPlayerNode: AVAudioPlayerNode?
    private var playbackEngine: AVAudioEngine?

    func playAudioData(_ data: Data) {
        // Gemini Live returns raw PCM audio at 24kHz, 16-bit, mono
        playPCMAudio(data, sampleRate: 24000)
    }

    private func playPCMAudio(_ data: Data, sampleRate: Double) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)

            // Create audio format for PCM 16-bit mono
            guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: sampleRate,
                                              channels: 1,
                                              interleaved: true) else {
                print("❌ Failed to create audio format")
                return
            }

            // Create buffer from data
            let frameCount = UInt32(data.count / 2)  // 16-bit = 2 bytes per sample
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("❌ Failed to create audio buffer")
                return
            }
            buffer.frameLength = frameCount

            // Copy data to buffer
            data.withUnsafeBytes { rawBufferPointer in
                if let int16Ptr = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Int16.self) {
                    buffer.int16ChannelData?[0].update(from: int16Ptr, count: Int(frameCount))
                }
            }

            // Create playback engine
            playbackEngine = AVAudioEngine()
            audioPlayerNode = AVAudioPlayerNode()

            guard let engine = playbackEngine, let player = audioPlayerNode else { return }

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            try engine.start()

            DispatchQueue.main.async {
                self.isSpeaking = true
            }

            player.play()
            player.scheduleBuffer(buffer) { [weak self] in
                DispatchQueue.main.async {
                    self?.isSpeaking = false
                    self?.playbackEngine?.stop()
                }
            }
        } catch {
            print("❌ PCM playback error: \(error.localizedDescription)")
            // Fall back to standard audio player
            playStandardAudio(data)
        }
    }

    private func playStandardAudio(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            DispatchQueue.main.async {
                self.isSpeaking = true
            }
        } catch {
            print("❌ Audio playback error: \(error.localizedDescription)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.speakContinuation?.resume()
            self.speakContinuation = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.speakContinuation?.resume()
            self.speakContinuation = nil
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension SpeechService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
