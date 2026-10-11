// MIT. Run in each user's GUI session; never kill unrelated applications.
import AppKit
import Foundation

@main
struct SessionControl {
    @MainActor static func main() {
        let targets = [
            (Identifiers.appBundleID, "/Applications/RockType.app"),
            (Identifiers.inputMethodBundleID, "/Library/Input Methods/RockType Input.app")
        ]
        for (identifier, path) in targets {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                where app.bundleURL?.standardizedFileURL.path == path {
                _ = app.terminate()
                let deadline = Date().addingTimeInterval(8)
                while !app.isTerminated && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
                guard app.isTerminated else {
                    FileHandle.standardError.write(Data("RockType: quit both applications before retrying installation.\n".utf8))
                    exit(1)
                }
            }
        }
    }
}
