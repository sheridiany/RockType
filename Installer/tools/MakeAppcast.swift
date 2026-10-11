import Foundation

@main
struct MakeAppcast {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 6 else { throw AppcastDocument.Failure.invalidMetadata }
            let package = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
            let expanded = URL(fileURLWithPath: args[2])
            let candidates = FileManager.default.enumerator(at: expanded, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.path.hasSuffix("/RoarkT.app/Contents/Info.plist") } ?? []
            guard candidates.count == 1,
                  let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: candidates[0]), format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == Identifiers.appBundleID else { throw AppcastDocument.Failure.invalidMetadata }
            let document = try AppcastDocument.render(package: package, info: info, download: args[3], signature: args[4])
            try document.write(to: URL(fileURLWithPath: args[5]), atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("Appcast generation failed: verify package metadata, download URL, and the public key embedded in the packaged app.\n".utf8))
            exit(1)
        }
    }
}
