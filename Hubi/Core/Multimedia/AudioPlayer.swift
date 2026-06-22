import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlayer: NSObject {
    static let shared = AudioPlayer()

    private var player: AVAudioPlayer?
    var isPlaying: Bool = false
    var progress: Double = 0    // 0..1
    var currentURL: URL?
    private var timer: Timer?

    func play(url: URL) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.currentURL = url
            self.isPlaying = true
            startTimer()
        } catch {
            AppLogger.shared.error("AudioPlayer 播放失败: \(error)")
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        currentURL = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
