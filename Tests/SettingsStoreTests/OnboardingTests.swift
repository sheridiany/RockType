import Foundation
import RoarkTCore
import Testing
@testable import RoarkTApp

struct OnboardingTests {
    @MainActor @Test func inputVerificationRejectsStaleEvidence() async {
        let pinyin = Identifiers.pinyinInputSourceID
        let flypy = Identifiers.flypyInputSourceID
        var source = InputSourceSnapshot(addedIDs: [pinyin, flypy], selectedID: pinyin)
        let epoch = UUID()
        var counter = TranslationServiceClient.InputGeneration(connectionID: epoch, value: 9)
        var calls = 0
        var fails = false
        var suspended: CheckedContinuation<TranslationServiceClient.InputGeneration, Error>?
        var suspendNext = false
        var disconnects = 0
        let manager = InputSourceManager(readSources: { source }, disconnect: { disconnects += 1 }, generation: {
            calls += 1
            if fails { throw TranslationServiceClient.Failure.disconnected }
            if suspendNext {
                suspendNext = false
                return try await withCheckedThrowingContinuation { suspended = $0 }
            }
            return counter
        })
        check(!manager.verified, "registration alone must not verify input")
        source.selectedID = "com.apple.keylayout.ABC"
        await manager.beginVerification()
        check(calls == 0 && !manager.isVerifying, "other source must not start verification")
        source.selectedID = pinyin
        await manager.beginVerification()
        await manager.verify()
        check(!manager.verified, "unchanged counter must not verify")
        counter = .init(connectionID: epoch, value: 10)
        await manager.verify()
        check(manager.verified, "fresh controller input must verify")
        source.selectedID = flypy
        manager.refresh()
        check(!manager.verified, "source switch must invalidate evidence")
        await manager.beginVerification()
        counter = .init(connectionID: UUID(), value: 100)
        await manager.verify()
        check(!manager.verified && !manager.isVerifying, "reconnect with larger counter must not verify")
        await manager.beginVerification()
        counter = .init(connectionID: counter.connectionID, value: 0)
        await manager.verify()
        check(!manager.verified && !manager.isVerifying, "counter reset must require fresh baseline")
        fails = true
        await manager.beginVerification()
        check(!manager.isVerifying, "connection failure must allow retry")
        fails = false
        suspendNext = true
        let oldAttempt = Task { await manager.beginVerification() }
        while suspended == nil { await Task.yield() }
        manager.cancel()
        suspended?.resume(returning: counter)
        await oldAttempt.value
        check(!manager.verified && !manager.isVerifying, "late baseline after skip must be ignored")
        await manager.beginVerification()
        suspendNext = true
        let oldVerification = Task { await manager.verify() }
        suspended = nil
        while suspended == nil { await Task.yield() }
        manager.stop()
        suspended?.resume(returning: .init(connectionID: counter.connectionID, value: 200))
        await oldVerification.value
        check(!manager.verified && disconnects == 1, "closing must release connection and ignore late verification")
    }

    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        #expect(condition(), Comment(rawValue: message))
    }
}

@MainActor @Test func onboardingSkipPersistsAndRerunDoesNotResetFirstLaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    let store = SettingsStore(persistence: persistence)
    let flow = OnboardingFlow(store: store)
    #expect(flow.shouldPresentAutomatically)
    // Jumping to the last step must not silently complete the other four.
    flow.select(.ai)
    flow.resolve(.skipped)
    #expect(!flow.finished && flow.step == .input)
    for _ in 0..<4 { flow.resolve(.skipped) }
    #expect(flow.finished && !flow.shouldPresentAutomatically)
    #expect(try persistence.load().settings.general.onboardingCompleted)
    flow.restart()
    #expect(!flow.finished && flow.step == .input && flow.resolutions.isEmpty)
    #expect(!flow.shouldPresentAutomatically)
    let reloaded = OnboardingFlow(store: SettingsStore(persistence: persistence))
    #expect(!reloaded.shouldPresentAutomatically)
}

@MainActor @Test func onboardingSaveFailureDoesNotClaimCompletionAndCanRetry() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blocker = directory.appendingPathComponent("blocked")
    try Data().write(to: blocker) // A file cannot be the settings parent directory.
    let persistence = SettingsPersistence(fileURL: blocker.appendingPathComponent("settings.json"))
    let store = SettingsStore(persistence: persistence)
    let flow = OnboardingFlow(store: store)
    for _ in 0..<5 { flow.resolve(.skipped) }
    #expect(!flow.finished && flow.errorMessage != nil && flow.shouldPresentAutomatically)
    try FileManager.default.removeItem(at: blocker)
    flow.resolve(.skipped)
    #expect(flow.finished)
    #expect(try persistence.load().settings.general.onboardingCompleted)
}

@MainActor @Test func settingsLaunchTakesPriorityAndGalleryDoesNotOpenOnboarding() {
    typealias Controller = OnboardingWindowController
    #expect(Controller.launchAction(arguments: [], completed: false) == .onboarding)
    #expect(Controller.launchAction(arguments: [], completed: true) == .none)
    #expect(Controller.launchAction(arguments: ["--show-settings"], completed: false) == .settings)
    #expect(Controller.launchAction(arguments: ["--show-settings"], completed: true) == .settings)
    #expect(Controller.launchAction(arguments: ["--gallery"], completed: false) == .none)
    #expect(Controller.launchAction(arguments: ["--render-gallery", "/tmp/gallery"], completed: false) == .none)
}
