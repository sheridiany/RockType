import Foundation
#if canImport(RoarkTCore)
import RoarkTCore
#endif

/// Shared with the standalone cleanup helper. Never follows a symlinked Rime directory.
enum UninstallData {
    static func remove(in home: URL, fileManager fm: FileManager = .default) throws {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        // Refuse a redirected ancestor; deleting a named symlink itself is safe.
        for parent in [home, library, support] {
            if (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        let appData = support.appendingPathComponent(Identifiers.applicationSupportFolder, isDirectory: true)
        let rime = Identifiers.rimeUserDirectory(home: home)
        // Check before deleting anything: the private Rime profile lives inside appData.
        for directory in [appData, rime.deletingLastPathComponent(), rime] {
            if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        if fm.fileExists(atPath: rime.path) { try fm.removeItem(at: rime) }
        if fm.fileExists(atPath: appData.path) { try fm.removeItem(at: appData) }
    }
}
