// Shared MIT ticket state. See LICENSE.md.
import Foundation

/// Single-use permission to insert into one unchanged native input context.
public struct VoiceCommitTicket: Sendable {
    public struct Context: Equatable, Sendable {
        public let activation: UUID
        public let applicationPID: Int32
        public let selection: NSRange

        public init(activation: UUID, applicationPID: Int32, selection: NSRange) {
            self.activation = activation
            self.applicationPID = applicationPID
            self.selection = selection
        }
    }

    private struct Pending: Sendable {
        let token: String
        let context: Context
        let expires: TimeInterval
    }
    private var pending: Pending?
    public init() {}

    public mutating func capture(_ context: Context, now: TimeInterval) -> String {
        let token = UUID().uuidString
        pending = Pending(token: token, context: context, expires: now + 120)
        return token
    }

    public mutating func cancel(_ token: String? = nil) {
        if token == nil || pending?.token == token { pending = nil }
    }

    public mutating func consume(_ token: String, context: Context, now: TimeInterval,
                                 deadline: TimeInterval = .greatestFiniteMagnitude) -> Bool {
        guard let pending, pending.token == token else { return false }
        self.pending = nil
        return pending.context == context && deadline.isFinite && now <= min(pending.expires, deadline)
    }
}
