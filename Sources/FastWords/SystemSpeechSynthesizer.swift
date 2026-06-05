import AVFoundation
import FastWordsCore

/// System text-to-speech via `AVSpeechSynthesizer`. Fully offline and free.
@MainActor
final class SystemSpeechSynthesizer: PronunciationService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, accent: SpeechAccent, rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.languageCode)

        // Map the 0...1 setting onto the synthesizer's supported range so the
        // slider feels natural rather than clamping at the extremes.
        let span = AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate
        let clamped = min(max(rate, 0), 1)
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate + Float(clamped) * span

        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
