// SoundManager.swift
// SlapMac – Sound Playback
//
// Plays a RANDOM slap sound on each detection (no intensity mapping).
// Also handles USB connect/disconnect sounds.
//
// ── HOW TO ADD MORE SOUNDS ──
// 1. Drop your .mp3 or .wav file into Resources/Audios/ in Xcode's navigator
//    (make sure "Copy items if needed" is checked and the target is selected)
// 2. Name it with the prefix "slap_" — e.g. slap_bonk.wav, slap_thud.mp3
//    ⚠️ The "slap_" prefix is REQUIRED — files without it are ignored!
// 3. Build and run — it will automatically be included in the random rotation!

import AVFoundation

class SoundManager {
    static let shared = SoundManager()

    private var activePlayers: [AVAudioPlayer] = []

    // ╔══════════════════════════════════════════════════════════╗
    // ║  DYNAMIC SOUND LOADING                                  ║
    // ║  Automatically finds any file starting with "slap_"     ║
    // ╚══════════════════════════════════════════════════════════╝
    private lazy var slapSounds: [String] = {
        let allowedExtensions = ["mp3", "wav", "m4a", "aiff"]
        var foundSounds: [String] = []
        
        for ext in allowedExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                let names = urls.map { $0.deletingPathExtension().lastPathComponent }
                foundSounds.append(contentsOf: names.filter { $0.hasPrefix("slap_") })
            }
        }
        
        if foundSounds.isEmpty {
            return ["slap_soft", "slap_medium", "slap_hard"]
        }
        return Array(Set(foundSounds)).sorted()
    }()

    /// Tracks the last played index to avoid repeating the same sound twice in a row
    private var lastPlayedIndex: Int = -1

    private init() {}

    // MARK: - Public Interface

    /// Plays a random slap sound from the slapSounds list.
    func playSlap(intensity: Double) {
        guard !slapSounds.isEmpty else { return }

        // Pick a random sound, but avoid repeating the last one
        var index: Int
        if slapSounds.count == 1 {
            index = 0
        } else {
            repeat {
                index = Int.random(in: 0..<slapSounds.count)
            } while index == lastPlayedIndex
        }
        lastPlayedIndex = index

        let soundName = slapSounds[index]
        // Volume is still slightly varied by intensity for a natural feel
        let volume = Float(0.7 + intensity * 0.3)
        play(named: soundName, volume: volume)
    }

    func playUSB(connected: Bool) {
        play(named: connected ? "usb_connect" : "usb_disconnect", volume: 0.85)
    }

    // MARK: - Private

    private func play(named name: String, volume: Float) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") ??
            Bundle.main.url(forResource: name, withExtension: "wav") ??
            Bundle.main.url(forResource: name, withExtension: "m4a") ??
            Bundle.main.url(forResource: name, withExtension: "aiff") else {
            print("⚠️ SoundManager: missing sound resource '\(name)' (.mp3/.wav/.m4a/.aiff)")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            activePlayers.append(player)
            player.play()
            // Clean up finished players
            activePlayers.removeAll { !$0.isPlaying }
        } catch {
            print("⚠️ SoundManager: failed to play '\(name)': \(error.localizedDescription)")
        }
    }
}
