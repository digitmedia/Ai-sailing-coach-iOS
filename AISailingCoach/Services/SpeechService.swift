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

    // MARK: - Private Properties

    // Speech Recognition
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Text-to-Speech
    private let synthesizer = AVSpeechSynthesizer()

    // Audio Player for Gemini audio responses
    private var audioPlayer: AVAudioPlayer?

    // Callback for transcription results
    private var onTranscription: ((String?) -> Void)?

    // MARK: - Initialization

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        synthesizer.delegate = self
        requestPermissions()
    }

    // MARK: - Permissions

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not available")
                @unknown default:
                    break
                }
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Microphone access granted")
                } else {
                    print("Microphone access denied")
                }
            }
        }
    }

    // MARK: - Speech Recognition

    func startListening(onTranscription: @escaping (String?) -> Void) {
        self.onTranscription = onTranscription

        // Stop any existing recognition
        stopListening()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcription = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = transcription
                }

                // If final result, call callback
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onTranscription?(transcription)
                        self.stopListening()
                    }
                }
            }

            if let error = error {
                print("Recognition error: \(error)")
                DispatchQueue.main.async {
                    self.stopListening()
                }
            }
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate the format before installing tap
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("Invalid audio format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
            }
        } catch {
            print("Audio engine error: \(error)")
        }
    }

    func stopListening() {
        // Stop audio engine first
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Only remove tap if engine was running
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        DispatchQueue.main.async {
            self.isListening = false
        }
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
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1 // Slightly faster
                utterance.pitchMultiplier = 1.0
                utterance.volume = 1.0

                // Store continuation for delegate callback
                self.speakContinuation = continuation

                self.synthesizer.speak(utterance)
            }
        }
    }

    private var speakContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Audio Playback (for Gemini Live API audio)

    func playAudioData(_ data: Data) {
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)

            // Create and play audio
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            DispatchQueue.main.async {
                self.isSpeaking = true
            }
        } catch {
            print("Audio playback error: \(error)")
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

// MARK: - Audio Level Monitoring

extension SpeechService {
    /// Get current audio input level (for UI visualization)
    func getInputLevel() -> Float {
        guard audioEngine.isRunning else { return 0 }

        let inputNode = audioEngine.inputNode
        guard inputNode.outputFormat(forBus: 0).streamDescription.pointee.mChannelsPerFrame > 0 else {
            return 0
        }

        // This is a simplified level detection
        // For production, use a proper audio level meter
        return 0.5 // Placeholder
    }
}
