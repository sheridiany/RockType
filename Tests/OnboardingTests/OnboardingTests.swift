import Foundation
import RoarkTCore

@main
struct OnboardingTests {
    @MainActor static func main() async {
        let pinyin = Identifiers.pinyinInputSourceID
        let flypy = Identifiers.flypyInputSourceID
        var source = InputSourceSnapshot(addedIDs: [pinyin, flypy], selectedID: pinyin)
        let epoch = UUID()
        var counter = TranslationServiceClient.InputGeneration(connectionID: epoch, value: 9)
        var calls = 0
        var fails = false
        var suspended: CheckedContinuation<TranslationServiceClient.InputGeneration, Error>?
        var suspendNext = false
        let manager = InputSourceManager(readSources: { source }, generation: {
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
        manager.cancel()
        suspended?.resume(returning: .init(connectionID: counter.connectionID, value: 200))
        await oldVerification.value
        check(!manager.verified, "late verification after closing must be ignored")
        print("PASS: input source verification, source changes, restart, failure and late replies")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
