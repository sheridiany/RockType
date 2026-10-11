import AppKit
import Testing
@testable import RoarkTApp
import RoarkTCore
@testable import RoarkTPlatform

@MainActor @Test func selectionCaptureProtectsSourcesAndRejectsLateResults() async throws {
    let source = ContentSnapshot.Source(pid: 42, bundleID: "test.editor", applicationName: "Test")
    @MainActor final class State {
        var allowed = true
        var current = true
        var reads = 0
        var copies = 0
        var status: SelectionReader.Status = .success
        var afterCopy: () -> Void = {}
        var suspendCopy = false
        var resumeCopy: CheckedContinuation<Void, Never>?
    }
    let state = State()
    let capture = SelectionCapture(allowed: { state.allowed }, context: {
        .init(source: source, isCurrent: { state.current })
    }, read: {
        state.reads += 1
        return .init(status: state.status, text: "Synthetic selection", rect: CGRect(x: 10, y: 20, width: 30, height: 40))
    }, copy: {
        state.copies += 1
        if state.suspendCopy {
            await withCheckedContinuation { state.resumeCopy = $0 }
        } else {
            await Task.yield()
        }
        state.afterCopy()
        return "Synthetic fallback"
    }, primaryHeight: { 1000 })

    let direct = try await capture.capture()
    #expect(direct.snapshot.method == .accessibility && state.copies == 0)
    #expect(direct.snapshot.selectionRect == CGRect(x: 10, y: 940, width: 30, height: 40))
    state.allowed = false
    do { _ = try await capture.capture(); Issue.record("protected read") } catch {}
    #expect(state.reads == 1 && state.copies == 0)
    state.allowed = true
    state.status = .empty
    do { _ = try await capture.capture(); Issue.record("empty copied") } catch {}
    #expect(state.copies == 0)
    state.status = .unsupported
    let fallback = try await capture.capture()
    #expect(fallback.snapshot.method == .copyFallback && state.copies == 1)
    state.afterCopy = { state.current = false }
    do { _ = try await capture.capture(); Issue.record("changed source accepted") } catch {}
    state.current = true
    state.afterCopy = { state.allowed = false }
    do { _ = try await capture.capture(); Issue.record("protected result accepted") } catch {}
    state.allowed = true
    state.afterCopy = {}
    let pending = Task { try await capture.capture() }
    pending.cancel()
    do { _ = try await pending.value; Issue.record("cancelled result accepted") } catch is CancellationError {}
    state.suspendCopy = true
    let late = Task { try await capture.capture() }
    for _ in 0..<1000 where state.resumeCopy == nil { await Task.yield() }
    try #require(state.resumeCopy != nil)
    late.cancel()
    state.resumeCopy?.resume()
    state.resumeCopy = nil
    do { _ = try await late.value; Issue.record("late cancelled result accepted") } catch is CancellationError {}
    #expect(direct.snapshot.text == "Synthetic selection")
    #expect(!SelectionPolicy.permits("com.apple.finder", settings: SelectionSettings()))
    var settings = AppSettings()
    settings.selection.applicationFilter = .whitelist
    settings.selection.includedApplications = ["test.editor"]
    #expect(SelectionPolicy.permits("test.editor", settings: settings.selection))
    #expect(!SelectionPolicy.permits(nil, settings: settings.selection))
    settings.selection.toolbarActions = ["search", "translate", "translate", "image", "copy", "missing"]
    settings.selection.disabledActions = ["translate"]
    settings.templates.append(.init(id: "image", name: "Image", icon: "photo", prompt: "", input: .image))
    #expect(SelectionPolicy.actions(settings: settings) == ["search", "copy"])
}

@MainActor @Test(arguments: ["com.microsoft.VSCode", "com.google.Chrome", "com.apple.Terminal"])
func missingAXSelectionFallsBackWithoutWeakeningProtection(_ bundleID: String) async throws {
    var allowed = true, copies = 0
    var length: Int? = 12
    let capture = SelectionCapture(allowed: { allowed }, context: {
        .init(source: .init(pid: 42, bundleID: bundleID, applicationName: "Synthetic"), isCurrent: { true })
    }, read: { .init(status: SelectionReader.classify(text: "", selectionLength: length), text: "", rect: nil) },
    copy: { copies += 1; return "Synthetic fallback" })
    let selected = try await capture.capture()
    #expect(selected.snapshot.method == .copyFallback && copies == 1)
    length = nil
    _ = try await capture.capture()
    #expect(copies == 2)
    length = 0
    do { _ = try await capture.capture(); Issue.record("Known empty selection copied") } catch {}
    #expect(copies == 2)
    allowed = false; length = 12
    do { _ = try await capture.capture(); Issue.record("Protected selection copied") } catch {}
    #expect(copies == 2)
}
