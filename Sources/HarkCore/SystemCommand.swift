import Foundation

/// The few things Hark does to the Mac itself, which need no model: volume, mute, dark mode and the lock
/// screen. Each is a short phrase with one meaning, so rules settle it. Phrases that mention a volume
/// without a clear level, or a mode without a clear direction, are left to the rest of Hark.
public enum SystemCommand: Sendable, Equatable {
    case volume(Int)
    case mute(Bool)
    case appearance(String)
    case lock

    private static let mostWords = 8
    private static let levels: [String: Int] = ["max": 100, "maximum": 100, "full": 100, "half": 50, "zero": 0, "minimum": 0]

    public static func request(in transcript: String) -> SystemCommand? {
        let words = AppAction.tokens(transcript).filter { !["please", "can", "you", "could", "hey"].contains($0) }
        guard !words.isEmpty, words.count <= mostWords else { return nil }

        // Lock the screen: "lock the screen", "lock my mac".
        if words.first == "lock", words.contains(where: ["screen", "mac", "computer", "laptop"].contains) { return .lock }

        // Mute and unmute: "mute", "mute the sound", "unmute the volume".
        if words.first == "mute", words.dropFirst().allSatisfy(soundWords.contains) { return .mute(true) }
        if words.first == "unmute", words.dropFirst().allSatisfy(soundWords.contains) { return .mute(false) }

        // Volume: "set the volume to 30 percent", "volume 30", "volume to max".
        if words.contains("volume"), let level = level(in: words) { return .volume(level) }

        // Dark and light mode: "switch to dark mode", "turn off dark mode".
        for mode in ["dark", "light"] where containsRun([mode, "mode"], in: words) {
            let off = words.contains("off") || words.contains("disable")
            let other = mode == "dark" ? "light" : "dark"
            return .appearance(off ? other : mode)
        }
        return nil
    }

    private static let soundWords: Set<String> = ["the", "sound", "audio", "volume", "mac", "my", "sounds", "everything"]

    private static func level(in words: [String]) -> Int? {
        for word in words {
            if let number = Int(word), (0...100).contains(number) { return number }
            if let preset = levels[word] { return preset }
        }
        return nil
    }

    private static func containsRun(_ run: [String], in words: [String]) -> Bool {
        guard words.count >= run.count else { return false }
        return (0...(words.count - run.count)).contains { Array(words[$0..<($0 + run.count)]) == run }
    }
}
