import AppKit
import AVFoundation
import RoarkTCore
import RoarkTPlatform

@MainActor struct VoiceEnvironment {
    var settings: () -> VoiceSettings
    var allowed: () -> Bool
    var pid: () -> Int32?
    var held: () -> Bool
    var microphoneGranted: () -> Bool
    var validate: @MainActor (VoiceModel) async throws -> URL
    var shortcutEnabled: () -> Bool
    var modelPresent: (VoiceModel) -> Bool = { _ in true }
    var inputSourceSelected: () -> Bool = { false }
    var modelRevision: () -> Int = { 0 }
    var polish: @MainActor (String) async -> String = { $0 }

    static func system(store: SettingsStore, models: VoiceModelStore) -> Self {
        Self(settings: { store.settings.voice }, allowed: { SecureInput.status() == .allowed },
             pid: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
             held: { NSEvent.modifierFlags.contains(.function) },
             microphoneGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
             validate: { try await models.validate($0) },
             shortcutEnabled: { store.settings.shortcuts.bindings[.voiceHoldToTalk] == Shortcut(key: nil, modifiers: .function) },
             modelPresent: { models.isPresent($0) },
             inputSourceSelected: { InputSourceSnapshot.current().selectedRoarkTID != nil },
             modelRevision: { models.revision },
             polish: { await VoicePolisher(settings: { store.settings }).polish($0) })
    }
}
