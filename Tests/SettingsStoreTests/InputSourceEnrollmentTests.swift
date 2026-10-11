import Foundation
import Testing
@testable import RoarkTApp

@MainActor private final class EnrollmentFixture {
    var visible = false
    var registration: InputSourceEnrollment.Registration = .registered
    var registrations = 0
    var polls = 0
    var appearAfter = 2
    var opens: [Bool] = []
    var openSucceeds = true
    var environment: InputSourceEnrollment {
        .init(isRegistered: { self.visible }, register: {
            self.registrations += 1
            return self.registration
        }, pause: {
            self.polls += 1
            if self.polls == self.appearAfter { self.visible = true }
        }, openSettings: {
            self.opens.append($0)
            return self.openSucceeds
        })
    }
    func manager() -> InputSourceManager {
        InputSourceManager(readSources: { .init(addedIDs: [], selectedID: nil) },
                           enrollment: environment,
                           generation: { throw TranslationServiceClient.Failure.disconnected })
    }
}

@MainActor @Test func enrollmentRegistersOnceWaitsAndRefreshesSettingsOnce() async {
    let fixture = EnrollmentFixture()
    let input = fixture.manager()
    await input.prepareRegistration()
    #expect(fixture.registrations == 1 && fixture.polls == 2)
    #expect(!input.isRegistering && input.registrationMessage == nil)
    #expect(input.snapshot.addedIDs.isEmpty && !input.verified)
    await input.prepareRegistration()
    #expect(fixture.registrations == 1)
    fixture.openSucceeds = false
    await input.openKeyboardSettings()
    #expect(input.registrationMessage != nil)
    fixture.openSucceeds = true
    await input.openKeyboardSettings()
    await input.openKeyboardSettings()
    #expect(fixture.opens == [true, true, false], "Failed reopening must retain the stale-list flag")
}

@MainActor @Test func enrollmentAlreadyVisibleDoesNotRegisterOrRestartSettings() async {
    let fixture = EnrollmentFixture()
    fixture.visible = true
    let input = fixture.manager()
    await input.prepareRegistration()
    await input.openKeyboardSettings()
    #expect(fixture.registrations == 0 && fixture.polls == 0)
    #expect(fixture.opens == [false])
}

@MainActor @Test func enrollmentFailuresAreBoundedAndDoNotRetryRegistration() async {
    for result in [InputSourceEnrollment.Registration.notInstalled, .failed, .registered] {
        let fixture = EnrollmentFixture()
        fixture.registration = result
        fixture.appearAfter = 100
        let input = fixture.manager()
        await input.prepareRegistration()
        #expect(input.registrationMessage != nil)
        #expect(!input.isRegistering)
        #expect(fixture.polls <= 20)
        await input.prepareRegistration()
        #expect(fixture.registrations == 1)
    }
}
