import AppKit

/// Only automatic mouse gestures use this gate. Explicit shortcuts bypass it.
/// Once scrolling or a modifier taints a drag, releasing it cannot revive that drag.
struct SelectionGesture {
    private var active = false
    private var dragged = false
    private var blocked = false
    private var suppress = true

    mutating func begin(modifiers: NSEvent.ModifierFlags, suppress: Bool) {
        self.suppress = suppress
        active = true; dragged = false
        blocked = suppress && Self.modified(modifiers)
    }
    mutating func drag(modifiers: NSEvent.ModifierFlags) {
        guard active else { return }
        dragged = true
        modifiersChanged(modifiers)
    }
    mutating func modifiersChanged(_ modifiers: NSEvent.ModifierFlags) {
        if active && suppress && Self.modified(modifiers) { blocked = true }
    }
    mutating func scroll() { if active && suppress { blocked = true } }
    mutating func finish(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        defer { self = Self() }
        return active && !blocked && (dragged || clickCount >= 2) && (!suppress || !Self.modified(modifiers))
    }
    static func permitsText(_ text: String, suppress: Bool) -> Bool {
        !suppress || text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }
    private static func modified(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.shift, .control, .option, .command, .function]).isEmpty
    }
}
