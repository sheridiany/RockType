import AppKit
import AVFoundation

@MainActor public enum Permissions {
    public enum Kind: CaseIterable, Sendable { case accessibility, screenRecording, microphone }
    public enum Status: Equatable, Sendable { case granted, notGranted, notDetermined, denied, restricted }

    /// AX and screen recording expose a Boolean preflight, not the distinction between never asked and denied.
    public static func status(for permission: Kind) -> Status {
        switch permission {
        case .accessibility: return Accessibility.isTrusted() ? .granted : .notGranted
        case .screenRecording: return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .notGranted
            }
        }
    }

    public enum RequestFailure: Error { case missingMicrophoneUsageDescription }

    /// Never call from polling or startup. Authorization belongs to the signed main app.
    public static func request(_ permission: Kind) async throws {
        switch permission {
        case .accessibility:
            _ = Accessibility.isTrusted(prompt: true)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .microphone:
            guard let description = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
                  !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RequestFailure.missingMicrophoneUsageDescription
            }
            if status(for: .microphone) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else if status(for: .microphone) == .denied {
                _ = openSettings(for: .microphone)
            }
        }
    }

    public static func settingsURL(for permission: Kind) -> URL {
        let pane: String
        switch permission {
        case .accessibility: pane = "Privacy_Accessibility"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .microphone: pane = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane)!
    }

    @discardableResult public static func openSettings(for permission: Kind) -> Bool {
        NSWorkspace.shared.open(settingsURL(for: permission))
    }
}
