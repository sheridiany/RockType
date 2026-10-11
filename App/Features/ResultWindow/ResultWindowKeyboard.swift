import AppKit

enum ResultWindowKeyAction: Equatable {
    case passThrough, escape, ask, send, copy, copyAndReturn
    static func resolve(code: UInt16, text: String?, modifiers: NSEvent.ModifierFlags,
                        editingQuestion: Bool, markedText: Bool) -> Self {
        guard !markedText else { return .passThrough }
        if code == 53 { return .escape }
        if text == "l", modifiers == .command { return .ask }
        if code == 36 || code == 76 {
            if modifiers == .command { return editingQuestion ? .send : .copyAndReturn }
            if modifiers.isEmpty, !editingQuestion { return .copyAndReturn }
        }
        if text == "c", modifiers.isEmpty, !editingQuestion { return .copy }
        return .passThrough
    }
}
