import AppKit
import os
import InputMethodKit
import Security
import Carbon

// XPC entrypoints dispatch to main before accessing ticket/controller state.
final class RoarkTVoiceServer: NSObject, NSXPCListenerDelegate, RoarkTDictationXPCProtocol, @unchecked Sendable {
  private final class Reply<Value>: @unchecked Sendable {
    let call: (Value) -> Void
    init(_ call: @escaping (Value) -> Void) { self.call = call }
  }

  private static let log = Logger(subsystem: "com.roarkist.inputmethod.RoarkT", category: "voice")
  private let listener = NSXPCListener.anonymous()
  private var publisher: NSXPCConnection?
  private weak var controller: SquirrelInputController?
  private var activation = UUID()
  private var ticket = VoiceCommitTicket()
  private var ticketOwner: ObjectIdentifier?
  private var connections = Set<ObjectIdentifier>()
  private var publishAttempts = 0
  private var publication = UUID()

  override init() {
    super.init()
    listener.delegate = self
    listener.resume()
  }

  func activate(_ controller: SquirrelInputController) {
    dispatchPrecondition(condition: .onQueue(.main))
    self.controller = controller
    activation = UUID()
    ticket.cancel()
    publishAttempts = 0
    publish()
  }

  func deactivate(_ controller: SquirrelInputController) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard self.controller === controller else { return }
    self.controller = nil
    ticket.cancel()
    activation = UUID()
  }

  func handledInput() {
    dispatchPrecondition(condition: .onQueue(.main))
    ticket.cancel()
    if publisher == nil { publishAttempts = 0 }
    publish()
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: ROARKT_APP_BUNDLE_ID))
    connection.exportedInterface = NSXPCInterface(with: RoarkTDictationXPCProtocol.self)
    connection.exportedObject = self
    let ownerID = ObjectIdentifier(connection)
    DispatchQueue.main.async { [self] in connections.insert(ownerID) }
    connection.invalidationHandler = { [weak self] in
      guard let owner = self else { return }
      DispatchQueue.main.async {
        owner.connections.remove(ownerID)
        if owner.ticketOwner == ownerID { owner.ticket.cancel() }
      }
    }
    connection.resume()
    return true
  }

  func capture(applicationPID: Int32, withReply reply: @escaping (String?, String?) -> Void) {
    let response = Reply<(String?, String?)> { reply($0.0, $0.1) }
    let ownerID = NSXPCConnection.current().map(ObjectIdentifier.init)
    DispatchQueue.main.async { [self] in
      guard let ownerID, connections.contains(ownerID) else {
        Self.log.error("capture refused: caller connection not accepted")
        response.call((nil, nil)); return
      }
      guard let (context, client) = currentContext() else {
        response.call((nil, nil)); return
      }
      guard context.applicationPID == applicationPID else {
        Self.log.error("capture refused: frontmost pid \(context.applicationPID) != requested \(applicationPID)")
        response.call((nil, nil)); return
      }
      ticketOwner = ownerID
      let token = ticket.capture(context, now: ProcessInfo.processInfo.systemUptime, lifetime: VoiceCommitTicket.dictationLifetime)
      response.call((token, client.bundleIdentifier()))
    }
  }

  func commit(ticket token: String, text: String, deadline: TimeInterval, withReply reply: @escaping (Bool) -> Void) {
    let response = Reply(reply)
    let ownerID = NSXPCConnection.current().map(ObjectIdentifier.init)
    DispatchQueue.main.async { [self] in
      guard let ownerID, connections.contains(ownerID), ticketOwner == ownerID else {
        response.call(false)
        return
      }
      defer { ticket.cancel(token) }
      guard token.utf8.count <= 64, text.utf8.count <= 32_768,
            let (context, client) = currentContext(),
            VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: client.bundleIdentifier()),
            ticket.consume(token, context: context, now: ProcessInfo.processInfo.systemUptime, deadline: deadline) else {
        response.call(false)
        return
      }
      // Same native insertion route as keyboard candidates. No pasteboard or synthetic keys.
      client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
      response.call(true)
    }
  }

  func cancel(ticket token: String) {
    let ownerID = NSXPCConnection.current().map(ObjectIdentifier.init)
    DispatchQueue.main.async { [self] in
      if ownerID != nil, ticketOwner == ownerID { ticket.cancel(token) }
    }
  }

  @MainActor
  private func currentContext() -> (VoiceCommitTicket.Context, IMKTextInput)? {
    dispatchPrecondition(condition: .onQueue(.main))
    // Reasons are logged without any text content, to diagnose binding failures.
    guard !IsSecureEventInputEnabled() else { Self.log.error("capture refused: secure input"); return nil }
    guard let client = controller?.voiceClient else {
      Self.log.error("capture refused: no active input client (controller \(self.controller == nil ? "nil" : "set"))")
      return nil
    }
    guard let app = NSWorkspace.shared.frontmostApplication,
          app.bundleIdentifier == client.bundleIdentifier() else {
      Self.log.error("capture refused: frontmost \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none", privacy: .public) != client \(client.bundleIdentifier() ?? "none", privacy: .public)")
      return nil
    }
    let context = VoiceCommitTicket.Context(activation: activation, applicationPID: app.processIdentifier,
                                           selection: client.selectedRange())
    return (context, client)
  }

  private func publish() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard publisher == nil, controller != nil, publishAttempts < 3 else { return }
    publishAttempts += 1
    let connection = NSXPCConnection(machServiceName: ROARKT_TRANSLATION_SERVICE_NAME)
    connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: ROARKT_TRANSLATION_SERVICE_NAME))
    connection.remoteObjectInterface = NSXPCInterface(with: RoarkTTranslationXPCProtocol.self)
    let publicationID = UUID()
    publication = publicationID
    let interrupted: @Sendable () -> Void = { [weak self] in
      guard let owner = self else { return }
      DispatchQueue.main.async {
        guard owner.publication == publicationID, let previous = owner.publisher else { return }
        owner.publisher = nil
        previous.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { owner.publish() }
      }
    }
    connection.interruptionHandler = interrupted
    connection.invalidationHandler = interrupted
    publisher = connection
    connection.resume()
    let proxy = connection.remoteObjectProxyWithErrorHandler { _ in interrupted() } as? RoarkTTranslationXPCProtocol
    proxy?.registerDictationEndpoint(listener.endpoint)
  }
}
