import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceRecorder: NSObject {
    var isRecording: Bool = false
    var duration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            }
        }
    }

    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        r.record()
        self.recorder = r
        self.isRecording = true
        self.duration = 0
        startTimer()
        return url
    }

    func stop() -> URL? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        let url = recorder?.url
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        return url
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        if let url = recorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recorder?.stop()
        recorder = nil
        isRecording = false
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.duration += 0.1
            }
        }
    }
}
