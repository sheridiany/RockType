import Foundation
import RoarkTXPCProtocol

let delegate = TranslationXPCListenerDelegate()
let listener = NSXPCListener(machServiceName: ROARKT_TRANSLATION_SERVICE_NAME)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
