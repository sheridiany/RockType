import XCTest
@testable import RoarkTCore

final class InputSourceEnablementTests: XCTestCase {
    private let parent: [String: Any] = ["InputSourceKind": "Keyboard Input Method", "Bundle ID": Identifiers.inputMethodBundleID]
    private let pinyin: [String: Any] = ["InputSourceKind": "Input Mode", "Bundle ID": Identifiers.inputMethodBundleID, "Input Mode": Identifiers.pinyinInputSourceID]

    func testPersistentRecordsRequireMatchingParentAndModeNotHistoryOrOtherBundles() {
        XCTAssertFalse(PersistentInputSourceState(preference: nil).listReadable)
        XCTAssertFalse(PersistentInputSourceState(preference: [parent]).requiredSourcesEnabled)
        XCTAssertFalse(PersistentInputSourceState(preference: [pinyin]).requiredSourcesEnabled)
        XCTAssertTrue(PersistentInputSourceState(preference: [parent, pinyin]).requiredSourcesEnabled)
        var foreign = pinyin; foreign["Bundle ID"] = "example.other"
        XCTAssertFalse(PersistentInputSourceState(preference: [parent, foreign]).requiredSourcesEnabled)
        XCTAssertFalse(PersistentInputSourceState(preference: ["AppleSelectedInputSources": [parent, pinyin]]).requiredSourcesEnabled)
        XCTAssertFalse(PersistentInputSourceState(preference: [["InputSourceKind": "Input Mode", "Input Mode": Identifiers.pinyinInputSourceID]]).pinyinEnabled)
    }

    func testRuntimeEnabledButMissingPersistenceEnablesParentThenModeWithoutReregistering() throws {
        var calls: [String] = []
        let registered = Set(InputSourceEnablement.registeredIDs)
        try InputSourceEnablement.ensure(persistent: .init(preference: [] as [[String: Any]]),
            registered: { registered }, enabled: { registered },
            register: { XCTFail("Existing registration must be preserved") },
            enable: { calls.append($0) }, verifyFresh: { calls.count == 2 })
        XCTAssertEqual(calls, InputSourceEnablement.requiredIDs)
    }

    func testNoErrWithoutPersistentEntriesIsFailure() {
        let registered = Set(InputSourceEnablement.registeredIDs)
        XCTAssertThrowsError(try InputSourceEnablement.ensure(persistent: .init(preference: [] as [[String: Any]]),
            registered: { registered }, enabled: { registered }, register: {}, enable: { _ in }, verifyFresh: { false })) {
                guard case InputSourceEnablement.Failure.persistenceUnconfirmed = $0 else { return XCTFail("Wrong failure") }
            }
    }

    func testHealthyUpdateDoesNotRegisterEnableOrChangeSelection() throws {
        var verified = false
        let registered = Set(InputSourceEnablement.registeredIDs)
        try InputSourceEnablement.ensure(persistent: .init(preference: [parent, pinyin]),
            registered: { registered }, enabled: { registered },
            register: { XCTFail("No registration during healthy update") },
            enable: { _ in XCTFail("No redundant enable") }, verifyFresh: { verified = true; return true })
        XCTAssertTrue(verified)
    }

    func testFirstInstallRegistersBeforeEnablingAndStopsOnParentFailure() {
        var registered = Set<String>(), calls: [String] = []
        XCTAssertThrowsError(try InputSourceEnablement.ensure(persistent: .init(preference: nil),
            registered: { registered }, enabled: { [] },
            register: { calls.append("register"); registered = Set(InputSourceEnablement.registeredIDs) },
            enable: { calls.append($0); throw NSError(domain: "synthetic", code: -50) },
            verifyFresh: { XCTFail("Cannot verify a failed API sequence"); return true }))
        XCTAssertEqual(calls, ["register", Identifiers.inputMethodBundleID])
    }

    func testIncompleteRegistrationNeverAttemptsEnable() {
        XCTAssertThrowsError(try InputSourceEnablement.ensure(persistent: .init(preference: nil),
            registered: { [] }, enabled: { [] }, register: {},
            enable: { _ in XCTFail("No source to enable") }, verifyFresh: { false }))
    }
}
