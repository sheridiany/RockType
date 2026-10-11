import AppKit

/// The overlay owns only these chords. Native text composition bypasses this map entirely.
enum CaptureKeyCommand: Equatable {
    case cancel, copy, quickSave, saveAs, pin, restore, ocrCopy, copyColor
    case undo, redo, delete, tool(ScreenshotTool?)
    case hierarchy(parent: Bool)
    case nudge(CaptureDirection, CaptureEdge?, fast: Bool)
}
enum CaptureDirection: CaseIterable { case left, right, up, down
    func delta(step: CGFloat) -> CGSize {
        switch self {
        case .left: CGSize(width: -step, height: 0)
        case .right: CGSize(width: step, height: 0)
        case .up: CGSize(width: 0, height: -step)
        case .down: CGSize(width: 0, height: step)
        }
    }
}
enum CaptureEdge { case leading, trailing }
enum CaptureKeyboard {
    static func command(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> CaptureKeyCommand? {
        let flags = modifiers.intersection([.command, .control, .option, .shift])
        let text = characters?.lowercased()
        if keyCode == 53 { return .cancel }
        if keyCode == 48, flags.isEmpty || flags == .shift { return .hierarchy(parent: flags.isEmpty) }
        if flags == .command {
            if text == "c" { return .copy }
            if text == "s" { return .saveAs }
        }
        // Preserve the previous undo/redo handling even with additional modifiers.
        if flags.contains(.command), text == "z" { return flags.contains(.shift) ? .redo : .undo }
        if keyCode == 36 || keyCode == 76 {
            if flags.isEmpty { return .copy }
            if flags == .shift { return .quickSave }
        }
        if flags == .shift {
            if text == "c" { return .ocrCopy }
            if let tool = ScreenshotTool.shortcut(keyCode: keyCode) { return .tool(tool) }
        }
        if flags.isEmpty {
            switch text {
            case "c": return .copyColor
            case "p": return .pin
            case "r": return .restore
            case "e": return .tool(.eraser)
            case "v": return .tool(nil)
            default: break
            }
            if keyCode == 51 || keyCode == 117 { return .delete }
        }
        let direction: CaptureDirection
        switch keyCode {
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: return nil
        }
        let edgeFlags = flags.subtracting(.shift)
        switch edgeFlags {
        case []: return .nudge(direction, nil, fast: flags.contains(.shift))
        case .option: return .nudge(direction, .leading, fast: flags.contains(.shift))
        case .command: return .nudge(direction, .trailing, fast: flags.contains(.shift))
        default: return .nudge(direction, nil, fast: flags.contains(.shift))
        }
    }
}
