import Foundation

enum iCloudSyncService {
    static let userDefaultsKey = "iCloudSyncEnabled"
    
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }
    
    static var localDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("FastWords", isDirectory: true)
    }
    
    static var cloudDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/FastWords", isDirectory: true)
    }
    
    static var activeDirectory: URL {
        isEnabled ? cloudDirectory : localDirectory
    }
    
    /// Migrates data between local and cloud directories based on the new setting
    static func performMigrationIfNeeded(toCloud: Bool) {
        let sourceDir = toCloud ? localDirectory : cloudDirectory
        let destDir = toCloud ? cloudDirectory : localDirectory
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceDir.path) else { return }
        
        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            
            // Only copy if destination doesn't have a state.json yet, 
            // to avoid overwriting existing cloud data when just enabling sync on a new device.
            let sourceState = sourceDir.appendingPathComponent("state.json")
            let destState = destDir.appendingPathComponent("state.json")
            
            if fm.fileExists(atPath: sourceState.path) && !fm.fileExists(atPath: destState.path) {
                try fm.copyItem(at: sourceState, to: destState)
            }
            
            // Copy audio files if they don't exist
            let sourceAudio = sourceDir.appendingPathComponent("audio")
            let destAudio = destDir.appendingPathComponent("audio")
            if fm.fileExists(atPath: sourceAudio.path) {
                if !fm.fileExists(atPath: destAudio.path) {
                    try fm.copyItem(at: sourceAudio, to: destAudio)
                } else {
                    // Could iterate and copy missing ones, but keeping it simple for now
                }
            }
        } catch {
            print("Migration failed: \(error)")
        }
    }
}
