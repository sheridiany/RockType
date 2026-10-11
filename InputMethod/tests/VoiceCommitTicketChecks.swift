import Foundation

@main
struct VoiceCommitTicketChecks {
  static func main() {
    let context = VoiceCommitTicket.Context(activation: UUID(), applicationPID: 42,
                                           selection: NSRange(location: 3, length: 0))
    var ticket = VoiceCommitTicket()
    var token = ticket.capture(context, now: 10)
    precondition(ticket.consume(token, context: context, now: 11, deadline: 12))
    precondition(!ticket.consume(token, context: context, now: 11, deadline: 12), "Replay must fail")

    token = ticket.capture(context, now: 10)
    let switchedApp = VoiceCommitTicket.Context(activation: context.activation, applicationPID: 43,
                                                selection: context.selection)
    precondition(!ticket.consume(token, context: switchedApp, now: 11, deadline: 12))
    precondition(!ticket.consume(token, context: context, now: 11, deadline: 12), "Failed commit consumes authority")

    token = ticket.capture(context, now: 10)
    let movedCaret = VoiceCommitTicket.Context(activation: context.activation, applicationPID: 42,
                                               selection: NSRange(location: 4, length: 0))
    precondition(!ticket.consume(token, context: movedCaret, now: 11, deadline: 12))

    token = ticket.capture(context, now: 10)
    let reactivated = VoiceCommitTicket.Context(activation: UUID(), applicationPID: 42,
                                                selection: context.selection)
    precondition(!ticket.consume(token, context: reactivated, now: 11, deadline: 12))

    token = ticket.capture(context, now: 10)
    ticket.cancel()
    precondition(!ticket.consume(token, context: context, now: 11, deadline: 12))
    token = ticket.capture(context, now: 10)
    precondition(!ticket.consume(token, context: context, now: 131))
    token = ticket.capture(context, now: 10)
    precondition(!ticket.consume(token, context: context, now: 11, deadline: 10.5))
    token = ticket.capture(context, now: 10)
    precondition(!ticket.consume(token, context: context, now: 11, deadline: .nan))

    let old = ticket.capture(context, now: 10)
    token = ticket.capture(context, now: 11)
    precondition(!ticket.consume(old, context: context, now: 12))
    precondition(ticket.consume(token, context: context, now: 12))

    precondition(VoiceInsertionPolicy.allowsAutomaticInsertion(text: "测试 hello", applicationID: "com.apple.TextEdit"))
    for text in ["", "hello\nworld", "hello\tworld", "hello\u{1b}"] {
      precondition(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: "com.apple.TextEdit"))
    }
    precondition(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: "hello", applicationID: nil))
    print("PASS: ticket replay, focus/app/caret changes, cancellation, deadlines, supersession and control-character rejection")
  }
}
