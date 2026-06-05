import AVFoundation
import CryptoKit
import Foundation

/// Downloads and caches human pronunciation clips, then plays them.
/// Files live under the app-support `audio/` directory and are reused offline.
@MainActor
final class AudioCache {
    private let directory: URL
    private let session: URLSession
    private var player: AVAudioPlayer?

    init(directory: URL, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    /// Stable, filesystem-safe file name for a remote clip's URL.
    static func fileName(for remoteURL: URL) -> String {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).mp3"
    }

    func localURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func isCached(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: fileName).path)
    }

    /// Download a clip if not already cached, returning the cache file name.
    func ensureCached(_ remoteURL: URL) async throws -> String {
        let name = Self.fileName(for: remoteURL)
        let destination = localURL(for: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            return name
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (data, _) = try await session.data(from: remoteURL)
        try data.write(to: destination, options: [.atomic])
        return name
    }

    /// Play a cached clip. Returns false if the file is missing so the caller
    /// can fall back to text-to-speech.
    @discardableResult
    func play(fileName: String) -> Bool {
        let url = localURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            return true
        } catch {
            return false
        }
    }
}
