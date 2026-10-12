import Foundation

private final class Observation: @unchecked Sendable {
    let lock = NSLock()
    var reads = 0
    var failures = 0
    func record(valid: Bool) { lock.withLock { reads += 1; if !valid { failures += 1 } } }
}

@main enum AtomicReplacementProbe {
    static func main() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("RockType-swap-" + UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        func bundle(_ name: String, version: String) throws -> URL {
            let url = root.appendingPathComponent(name + ".app")
            try files.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": Identifiers.inputMethodBundleID], format: .xml, options: 0)
            try info.write(to: url.appendingPathComponent("Contents/Info.plist"))
            try Data(version.utf8).write(to: url.appendingPathComponent("Contents/version"))
            return url
        }
        let installed = try bundle("Installed", version: "old")
        let staged = try bundle("Staged", version: "new")
        let observation = Observation()
        let ready = DispatchSemaphore(value: 0), stop = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            ready.signal()
            repeat {
                let bytes = try? Data(contentsOf: installed.appendingPathComponent("Contents/version"))
                observation.record(valid: bytes == Data("old".utf8) || bytes == Data("new".utf8))
            } while stop.wait(timeout: .now()) != .success
            done.signal()
        }
        ready.wait()
        for _ in 0..<200 { try AtomicInputMethodReplacement.replace(staged: staged, destination: installed) }
        stop.signal(); done.wait()
        print("Concurrent reader: \(observation.reads) reads, \(observation.failures) missing/partial bundles")
        guard observation.reads > 0, observation.failures == 0 else { exit(1) }
        let inode = try files.attributesOfItem(atPath: staged.path)[.systemFileNumber] as! NSNumber
        try AtomicInputMethodReplacement.replace(staged: staged, destination: installed)
        let installedInode = try files.attributesOfItem(atPath: installed.path)[.systemFileNumber] as! NSNumber
        precondition(installedInode == inode)
        let first = root.appendingPathComponent("First.app")
        try AtomicInputMethodReplacement.replace(staged: staged, destination: first)
        precondition(!files.fileExists(atPath: staged.path))
        let before = try Data(contentsOf: installed.appendingPathComponent("Contents/version"))
        do {
            try AtomicInputMethodReplacement.replace(staged: staged, destination: installed)
            preconditionFailure("Missing staging bundle must fail")
        } catch { }
        let after = try Data(contentsOf: installed.appendingPathComponent("Contents/version"))
        precondition(after == before)
        let link = root.appendingPathComponent("Link.app")
        try files.createSymbolicLink(at: link, withDestinationURL: installed)
        do {
            try AtomicInputMethodReplacement.replace(staged: first, destination: link)
            preconditionFailure("Symlink destination must fail")
        } catch { }
        let afterLink = try Data(contentsOf: installed.appendingPathComponent("Contents/version"))
        precondition(afterLink == before)
        print("Atomic replacement, first install, missing staging and symlink refusal passed")
    }
}
