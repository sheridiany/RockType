// MIT. This tool registers, lists, disables or diagnoses RoarkT input sources.
// Registration never enables or selects an input source.
import Carbon
import Foundation

@main
struct RegisterInputSource {
    static let sourceIDs = [Identifiers.pinyinInputSourceID, Identifiers.flypyInputSourceID]

    static func sources() -> [TISInputSource] {
        let filter = [kTISPropertyBundleID as String: Identifiers.inputMethodBundleID] as CFDictionary
        return TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
    }

    static func identifier(_ source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(EXIT_FAILURE)
    }

    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fail("Usage: RoarkTRegisterInputSource register <bundle> | list | disable | diagnose-icons | check-icons <bundle>") }
        switch args[1] {
        case "diagnose-icons":
            guard args.count == 2 else { fail("diagnose-icons takes no arguments and is read-only") }
            exit(InputSourceIconDiagnostics.run(bundleURL: nil))
        case "check-icons":
            guard args.count == 3 else { fail("check-icons requires a bundle path and is read-only") }
            exit(InputSourceIconDiagnostics.run(bundleURL: URL(fileURLWithPath: args[2], isDirectory: true)))
        case "register":
            guard args.count == 3 else { fail("register requires an input method bundle path") }
            let url = URL(fileURLWithPath: args[2], isDirectory: true)
            guard Bundle(url: url)?.bundleIdentifier == Identifiers.inputMethodBundleID else {
                fail("Unexpected input method bundle identifier")
            }
            let status = TISRegisterInputSource(url as CFURL)
            guard status == noErr else { fail("TISRegisterInputSource failed: \(status)") }
            for _ in 0..<20 {
                let registered = Set(sources().compactMap(identifier))
                if sourceIDs.allSatisfy(registered.contains) {
                    sourceIDs.forEach { print($0) }
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            fail("Registration returned success, but both input sources are not visible yet; retry after logging in again")
        case "list":
            let registered = Set(sources().compactMap(identifier))
            sourceIDs.filter(registered.contains).forEach { print($0) }
            guard sourceIDs.allSatisfy(registered.contains) else { fail("Both RockType input sources are not registered") }
        case "disable":
            for source in sources() where sourceIDs.contains(identifier(source) ?? "") {
                guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
                      CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue()) else { continue }
                let status = TISDisableInputSource(source)
                guard status == noErr else { fail("TISDisableInputSource failed: \(status); select another input method and retry") }
            }
        default:
            fail("Unknown operation")
        }
    }
}
