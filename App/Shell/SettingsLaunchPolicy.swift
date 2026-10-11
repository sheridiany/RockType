/// Launching the app opens its useful configuration surface. Background and gallery
/// launches remain quiet; no completion flag or permission request gates entry.
enum SettingsLaunchPolicy {
    enum Action { case settings, none }
    static func action(arguments: [String]) -> Action {
        #if DEBUG
        if arguments.contains("--gallery") || arguments.contains("--render-gallery") { return .none }
        #endif
        if arguments.contains("--show-settings") { return .settings }
        if arguments.contains("--background") { return .none }
        return .settings
    }
}
