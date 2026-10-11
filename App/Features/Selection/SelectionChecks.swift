#if SELECTION_CHECKS
import AppKit
import RoarkTCore
import RoarkTPlatform

@main struct SelectionChecks {
    @MainActor static func main() async throws {
        let source = ContentSnapshot.Source(pid: 42, bundleID: "test.editor", applicationName: "Test")
        @MainActor final class State {
            var allowed = true
            var current = true
            var reads = 0
            var copies = 0
            var status: SelectionReader.Status = .success
            var afterCopy: () -> Void = {}
        }
        let state = State()
        let capture = SelectionCapture(allowed: { state.allowed }, context: {
            .init(source: source, isCurrent: { state.current })
        }, read: {
            state.reads += 1
            return .init(status: state.status, text: "Synthetic selection", rect: CGRect(x: 10, y: 20, width: 30, height: 40))
        }, copy: {
            state.copies += 1
            await Task.yield()
            state.afterCopy()
            return "Synthetic fallback"
        }, primaryHeight: { 1000 })

        let direct = try await capture.capture()
        precondition(direct.snapshot.method == .accessibility && state.copies == 0)
        precondition(direct.snapshot.selectionRect == CGRect(x: 10, y: 940, width: 30, height: 40))
        state.allowed = false
        do { _ = try await capture.capture(); fatalError("protected read") } catch {}
        precondition(state.reads == 1 && state.copies == 0)
        state.allowed = true
        state.status = .empty
        do { _ = try await capture.capture(); fatalError("empty copied") } catch {}
        precondition(state.copies == 0)
        state.status = .unsupported
        let fallback = try await capture.capture()
        precondition(fallback.snapshot.method == .copyFallback && state.copies == 1)
        state.afterCopy = { state.current = false }
        do { _ = try await capture.capture(); fatalError("changed source accepted") } catch {}
        state.current = true
        state.afterCopy = { state.allowed = false }
        do { _ = try await capture.capture(); fatalError("protected result accepted") } catch {}
        state.allowed = true
        state.afterCopy = {}
        let pending = Task { try await capture.capture() }
        pending.cancel()
        do { _ = try await pending.value; fatalError("cancelled result accepted") } catch is CancellationError {}
        precondition(direct.snapshot.text == "Synthetic selection")
        precondition(!SelectionPolicy.permits("com.apple.finder", settings: SelectionSettings()))
        var settings = AppSettings()
        settings.selection.applicationFilter = .whitelist
        settings.selection.includedApplications = ["test.editor"]
        precondition(SelectionPolicy.permits("test.editor", settings: settings.selection))
        precondition(!SelectionPolicy.permits(nil, settings: settings.selection))
        settings.selection.toolbarActions = ["search", "translate", "translate", "image", "copy", "missing"]
        settings.selection.disabledActions = ["translate"]
        settings.templates.append(.init(id: "image", name: "Image", icon: "photo", prompt: "", input: .image))
        precondition(SelectionPolicy.actions(settings: settings) == ["search", "copy"])
        print("Selection capture checks passed: direct, protected, empty, fallback, source change, cancellation, coordinates, filters, actions")
    }
}
#endif
