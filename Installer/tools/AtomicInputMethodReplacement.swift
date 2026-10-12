// MIT. Staging and destination are already on the same filesystem.
import Darwin
import Foundation

enum AtomicInputMethodReplacement {
    static func replace(staged: URL, destination: URL) throws {
        let files = FileManager.default
        guard staged.standardizedFileURL != destination.standardizedFileURL else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        func validate(_ url: URL) throws {
            let attributes = try files.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  Bundle(url: url)?.bundleIdentifier == Identifiers.inputMethodBundleID else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
            }
        }
        try validate(staged)
        let exists = files.fileExists(atPath: destination.path)
        if exists { try validate(destination) }
        // Never unlink an installed bundle: TIS may refresh its UI-order cache at any time.
        // A swap leaves the previous bundle at the staging path for immediate cleanup.
        // RENAME_EXCL also refuses a destination created concurrently during first install.
        let flags = UInt32(exists ? RENAME_SWAP : RENAME_EXCL)
        guard renamex_np(staged.path, destination.path, flags) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
