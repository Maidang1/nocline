import Foundation
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "EmotionState")

@MainActor
@Observable
final class EmotionState {
    private(set) var currentEmotion: NotchiEmotion = .neutral
    private(set) var scores: [NotchiEmotion: Double] = [
        .happy: 0.0,
        .sad: 0.0
    ]

    static let emotionChangeThreshold = 0.6
    static let intensityDampen = 0.5
    static let decayRate = 0.9
    static let interEmotionDecay = 0.9
    static let neutralCounterDecay = 0.7
    static let decayInterval: Duration = .seconds(60)

    private var scoresDescription: String {
        scores
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
            .map { "\($0.key.rawValue): \(String(format: "%.2f", $0.value))" }
            .joined(separator: ", ")
    }

    init() {}

    func recordEmotion(_ rawEmotion: String, intensity: Double, prompt: String) {
        let emotion = NotchiEmotion(rawValue: rawEmotion)

        if let emotion, emotion != .neutral {
            let dampened = intensity * Self.intensityDampen
            scores[emotion, default: 0.0] = min(scores[emotion, default: 0.0] + dampened, 1.0)
            for key in scores.keys where key != emotion {
                scores[key, default: 0.0] *= Self.interEmotionDecay
            }
        } else {
            // Neutral or unknown: actively counter all non-neutral scores
            for key in scores.keys {
                scores[key, default: 0.0] *= Self.neutralCounterDecay
            }
        }

        updateCurrentEmotion()

        let truncatedPrompt = String(prompt.prefix(60))
        logger.info("[Emotion] \"\(truncatedPrompt, privacy: .public)\" → detected: \(rawEmotion, privacy: .public) (\(String(format: "%.2f", intensity), privacy: .public)) → cumulative: {\(self.scoresDescription, privacy: .public)}")
    }

    func decayAll() {
        var anyChanged = false
        for key in scores.keys {
            let old = scores[key, default: 0.0]
            let new = old * Self.decayRate
            scores[key] = new < 0.01 ? 0.0 : new
            if scores[key] != old { anyChanged = true }
        }

        if anyChanged {
            updateCurrentEmotion()
            logger.debug("[Emotion] decay → {\(self.scoresDescription, privacy: .public)} → current: \(self.currentEmotion.rawValue, privacy: .public)")
        }
    }

    private func updateCurrentEmotion() {
        let best = scores.max(by: { $0.value < $1.value })

        if let best, best.value >= Self.emotionChangeThreshold {
            currentEmotion = best.key
        } else {
            currentEmotion = .neutral
        }
    }
}
