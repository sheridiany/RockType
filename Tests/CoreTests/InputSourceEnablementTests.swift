import XCTest
@testable import RoarkTCore

final class InputSourceEnablementTests: XCTestCase {
    private let all = Set(InputSourceEnablement.registeredIDs)
    private let required = Set(InputSourceEnablement.requiredIDs)
    private func state(enabled: Set<String>) -> InputSourceEnablementState {
        .init(registered: all, enabled: enabled, selectable: [Identifiers.pinyinInputSourceID, Identifiers.flypyInputSourceID])
    }

    func testHealthyTISWithMissingLegacyPreferencesDoesNotReregisterOrEnable() throws {
        let legacy = InputSourcePreferenceEvidence(preference: [] as [[String: Any]])
        XCTAssertFalse(legacy.parentEnabled)
        XCTAssertFalse(legacy.pinyinEnabled)
        let healthy = state(enabled: required)
        XCTAssertTrue(healthy.verificationPassed)
        var verified = false
        try InputSourceEnablement.ensure(state: { healthy },
            register: { XCTFail("Healthy update must not register again") },
            enable: { _ in XCTFail("Stale preference files must not trigger enable calls") },
            verifyFresh: { verified = true; return healthy.verificationPassed })
        XCTAssertTrue(verified)
    }

    func testVerificationRequiresParentAndSelectablePinyinButNotParentSelectabilityOrFlypyEnablement() {
        XCTAssertTrue(state(enabled: required).verificationPassed)
        XCTAssertFalse(state(enabled: [Identifiers.pinyinInputSourceID]).verificationPassed)
        XCTAssertFalse(state(enabled: [Identifiers.inputMethodBundleID]).verificationPassed)
        XCTAssertFalse(InputSourceEnablementState(registered: all, enabled: required, selectable: []).verificationPassed)
        XCTAssertFalse(InputSourceEnablementState(registered: [], enabled: required, selectable: [Identifiers.pinyinInputSourceID]).verificationPassed)
    }

    func testDisabledSourcesEnableParentThenModeWithoutReregistering() throws {
        var calls: [String] = [], enabled = Set<String>()
        try InputSourceEnablement.ensure(state: { self.state(enabled: enabled) },
            register: { XCTFail("Existing registration must be preserved") },
            enable: { calls.append($0); enabled.insert($0) }, verifyFresh: { self.state(enabled: enabled).verificationPassed })
        XCTAssertEqual(calls, InputSourceEnablement.requiredIDs)
    }

    func testNoErrWithoutFreshUsableStateIsFailure() {
        XCTAssertThrowsError(try InputSourceEnablement.ensure(state: { self.state(enabled: []) },
            register: {}, enable: { _ in }, verifyFresh: { false })) {
                guard case InputSourceEnablement.Failure.enablementUnconfirmed = $0 else { return XCTFail("Wrong failure") }
            }
    }

    func testFirstInstallRegistersBeforeEnablingAndStopsOnParentFailure() {
        var registered = Set<String>(), calls: [String] = []
        XCTAssertThrowsError(try InputSourceEnablement.ensure(
            state: { .init(registered: registered, enabled: [], selectable: []) },
            register: { calls.append("register"); registered = self.all },
            enable: { calls.append($0); throw NSError(domain: "synthetic", code: -50) },
            verifyFresh: { XCTFail("Cannot verify a failed API sequence"); return true }))
        XCTAssertEqual(calls, ["register", Identifiers.inputMethodBundleID])
    }

    func testIncompleteRegistrationNeverAttemptsEnable() {
        XCTAssertThrowsError(try InputSourceEnablement.ensure(
            state: { .init(registered: [], enabled: [], selectable: []) }, register: {},
            enable: { _ in XCTFail("No source to enable") }, verifyFresh: { false }))
    }

    func testPreferenceEvidenceMatchesBundleAndModeWithoutInferringSystemHealth() {
        let parent: [String: Any] = ["InputSourceKind": "Keyboard Input Method", "Bundle ID": Identifiers.inputMethodBundleID]
        let pinyin: [String: Any] = ["InputSourceKind": "Input Mode", "Bundle ID": Identifiers.inputMethodBundleID, "Input Mode": Identifiers.pinyinInputSourceID]
        let modern = InputSourcePreferenceEvidence(preference: [parent, pinyin])
        XCTAssertTrue(modern.parentEnabled && modern.pinyinEnabled)
        XCTAssertFalse(modern.flypyEnabled)
        var foreign = pinyin; foreign["Bundle ID"] = "example.other"
        XCTAssertFalse(InputSourcePreferenceEvidence(preference: [parent, foreign]).pinyinEnabled)
        XCTAssertFalse(InputSourcePreferenceEvidence(preference: nil).listReadable)
    }
}
