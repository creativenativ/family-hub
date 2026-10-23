import AVFoundation
import Foundation
import Observation

@Observable
final class VoiceMemoAudioController: NSObject {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?

    var isRecording = false
    var isPlaying = false
    var recordingElapsed: TimeInterval = 0
    var playbackProgress: Double = 0
    var errorMessage: String?
    var currentlyPlayingID: UUID?

    private var elapsedTimer: Timer?
    private var playbackTimer: Timer?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() throws {
        stopPlayback()
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-memo-\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        isRecording = true
        recordingStartedAt = Date()
        recordingElapsed = 0

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let started = self.recordingStartedAt else { return }
            self.recordingElapsed = Date().timeIntervalSince(started)
        }
    }

    func stopRecording() -> (data: Data, duration: TimeInterval)? {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isRecording = false

        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil

        guard let url = recordingURL,
              let data = try? Data(contentsOf: url) else { return nil }

        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        recordingStartedAt = nil

        return (data, max(duration, 0.5))
    }

    func cancelRecording() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isRecording = false
        recorder?.stop()
        recorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingStartedAt = nil
        recordingElapsed = 0
    }

    func play(data: Data, memoID: UUID) {
        stopPlayback()
        errorMessage = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            currentlyPlayingID = memoID
            playbackProgress = 0

            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.playbackProgress = player.currentTime / player.duration
            }
        } catch {
            errorMessage = "Couldn't play this memo."
            isPlaying = false
            currentlyPlayingID = nil
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentlyPlayingID = nil
        playbackProgress = 0
    }

    func togglePlayback(data: Data, memoID: UUID) {
        if isPlaying && currentlyPlayingID == memoID {
            stopPlayback()
        } else {
            play(data: data, memoID: memoID)
        }
    }
}

extension VoiceMemoAudioController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopPlayback()
        }
    }
}
