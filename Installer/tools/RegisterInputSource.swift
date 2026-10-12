// MIT. This tool registers, lists, disables or diagnoses RoarkT input sources.
// register stays registration-only; ensure-enabled explicitly enables parent + Pinyin, never selects.
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

    @MainActor static func verifyFresh() -> Bool {
        // Each verifier enumerates public TIS state in a new process; no preference-file gate.
        for _ in 0..<20 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["verify-enabled"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit() } catch { return false }
            if process.terminationReason == .exit && process.terminationStatus == 0 { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fail("Usage: RoarkTRegisterInputSource register <bundle> | list | disable | diagnose-icons | check-icons <bundle> | replace-bundle <staged> <destination> | ensure-enabled <bundle> | verify-enabled") }
        switch args[1] {
        case "diagnose-icons":
            guard args.count == 2 else { fail("diagnose-icons takes no arguments and is read-only") }
            exit(InputSourceIconDiagnostics.run(bundleURL: nil))
        case "check-icons":
            guard args.count == 3 else { fail("check-icons requires a bundle path and is read-only") }
            exit(InputSourceIconDiagnostics.run(bundleURL: URL(fileURLWithPath: args[2], isDirectory: true)))
        case "replace-bundle":
            guard args.count == 4 else { fail("replace-bundle requires staged and destination paths") }
            do {
                try AtomicInputMethodReplacement.replace(
                    staged: URL(fileURLWithPath: args[2], isDirectory: true),
                    destination: URL(fileURLWithPath: args[3], isDirectory: true))
            } catch { fail("Atomic input method replacement failed: \(error)") }
        case "verify-enabled":
            guard args.count == 2 else { fail("verify-enabled takes no arguments and is read-only") }
            let state = InputSourceIconDiagnostics.enablement()
            if let data = try? JSONEncoder().encode(state) { FileHandle.standardOutput.write(data + Data("\n".utf8)) }
            guard state.verificationPassed else {
                fail("TIS verification failed: RockType parent must be registered/enabled and Pinyin registered/enabled/selectable. Add RockType Pinyin in System Settings > Keyboard > Text Input, then rerun verify-enabled. HIToolbox preferences were not edited directly.")
            }
        case "ensure-enabled":
            guard args.count == 3 else { fail("ensure-enabled requires an installed bundle path") }
            let url = URL(fileURLWithPath: args[2], isDirectory: true)
            guard Bundle(url: url)?.bundleIdentifier == Identifiers.inputMethodBundleID else { fail("Unexpected input method bundle identifier") }
            do {
                try InputSourceEnablement.ensure(
                    state: { InputSourceIconDiagnostics.enablement() },
                    register: {
                        let status = TISRegisterInputSource(url as CFURL)
                        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                        for _ in 0..<20 {
                            if Set(InputSourceEnablement.registeredIDs).isSubset(of: Set(sources().compactMap(identifier))) { break }
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                    },
                    enable: { id in
                        guard let source = sources().first(where: { identifier($0) == id }) else { throw InputSourceEnablement.Failure.registrationIncomplete }
                        let status = TISEnableInputSource(source)
                        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                    }, verifyFresh: { verifyFresh() })
                print("RockType parent and Pinyin passed fresh TIS enablement verification; selection unchanged.")
            } catch {
                fail("RockType enablement failed or TIS state was not confirmed: \(error). API success is insufficient. Add RockType Pinyin in System Settings > Keyboard > Text Input, then run verify-enabled. HIToolbox preferences were not edited directly.")
            }
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
            for id in sourceIDs + [Identifiers.inputMethodBundleID] {
                guard let source = sources().first(where: { identifier($0) == id }) else { continue }
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
