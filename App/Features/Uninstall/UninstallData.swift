import Foundation

/// Shared with the standalone cleanup helper. Never follows a symlinked Rime directory.
enum UninstallData {
    static func ownedRimeName(_ name: String) -> Bool {
        ["roarkt", "roarkt_flypy", "roarkt_en", "roarkt_zh"].contains { stem in
            name.hasPrefix(stem + ".")
        }
    }

    static func remove(in home: URL, fileManager fm: FileManager = .default) throws {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        // Refuse a redirected ancestor; deleting a named symlink itself is safe.
        for parent in [home, library, support] {
            if (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        let appData = support.appendingPathComponent("RoarkT", isDirectory: true)
        if fm.fileExists(atPath: appData.path) { try fm.removeItem(at: appData) }
        let rime = library.appendingPathComponent("Rime", isDirectory: true)
        guard fm.fileExists(atPath: rime.path) else { return }
        guard try rime.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        // Shared dictionaries, installation.yaml, user.yaml and unmarked custom files stay.
        for directory in [rime, rime.appendingPathComponent("build", isDirectory: true)] {
            guard fm.fileExists(atPath: directory.path),
                  try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
            for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where ownedRimeName(file.lastPathComponent) {
                // Only product-marked custom files are ours; user-authored patches stay.
                if file.lastPathComponent.hasSuffix(".custom.yaml") {
                    guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                          let contents = try? Data(contentsOf: file),
                          contents.starts(with: Data("# 由 RoarkT 生成；请通过 RoarkT 设置修改。\n".utf8)) else { continue }
                }
                try fm.removeItem(at: file)
            }
        }
        // Shared default.custom.yaml and squirrel.custom.yaml have no product ownership
        // marker in the current writer and are always preserved.
    }
}
