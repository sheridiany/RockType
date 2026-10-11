import AppKit
import SwiftUI

/// S2 retains this controller and passes the same permission/AI views used by Settings.
/// No parallel permission owner, AI form or settings file is created here.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let flow: OnboardingFlow
    private let input = InputSourceManager()
    private let language = LanguagePackModel()
    private let permissions: () -> AnyView
    private let aiConnection: () -> AnyView
    private let showSettings: () -> Void
    private var window: NSWindow?

    init(store: SettingsStore, permissions: @escaping () -> AnyView,
         aiConnection: @escaping () -> AnyView, showSettings: @escaping () -> Void) {
        flow = OnboardingFlow(store: store)
        self.permissions = permissions
        self.aiConnection = aiConnection
        self.showSettings = showSettings
        super.init()
    }

    /// Call once from AppDelegate.applicationDidFinishLaunching.
    func applicationDidFinishLaunching(arguments: [String] = CommandLine.arguments) {
        switch Self.launchAction(arguments: arguments, completed: !flow.shouldPresentAutomatically) {
        case .settings: showSettings()
        case .onboarding: show()
        case .none: break
        }
    }

    enum LaunchAction { case settings, onboarding, none }
    static func launchAction(arguments: [String], completed: Bool) -> LaunchAction {
        // Gallery rendering must never persist preferences or open another window.
        if arguments.contains("--render-gallery") || arguments.contains("--gallery") { return .none }
        if arguments.contains("--show-settings") { return .settings }
        return completed ? .none : .onboarding
    }

    /// NSWorkspace reopens an existing process rather than replacing its arguments.
    /// Forward AppDelegate.applicationShouldHandleReopen here to honor the IME menu.
    @discardableResult func applicationShouldHandleReopen() -> Bool {
        showSettings()
        return false
    }

    /// Settings → General calls this action; it does not clear the persisted completion bit.
    func rerun() { flow.restart(); show() }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingShellView(flow: flow, input: input, language: language,
                                      permissions: permissions, aiConnection: aiConnection,
                                      onFinish: { [weak self] in self?.window?.close() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Tokens.Size.settingsWidth,
                                                 height: Tokens.Size.settingsHeight),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "欢迎使用 RoarkT"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        input.cancel()
        // Release the SwiftUI tree so its tasks stop even when an NSWindow is retained.
        window?.contentView = nil
        window = nil
    }
}
