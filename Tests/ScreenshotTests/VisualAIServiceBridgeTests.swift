import AppKit
import XCTest
import RoarkTCore
@testable import RoarkTApp

private final class VisualWireRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data] = []
    func add(_ data: Data) { lock.withLock { values.append(data) } }
    func take() -> [Data] { lock.withLock { defer { values.removeAll() }; return values } }
}
private final class VisualWireProtocol: URLProtocol, @unchecked Sendable {
    static let recorder = VisualWireRecorder()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "synthetic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.recorder.add(data)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        let response = "data: {\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"Never display this reasoning\"}}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Synthetic visible answer\"}}]}\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didLoad: Data(response.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class VisualAIServiceBridgeTests: XCTestCase {
    @MainActor func testPreviewUsesProductionServiceForEveryActionAndDoesNotSendBeforeConfirmation() async throws {
        _ = VisualWireProtocol.recorder.take()
        let networkConfig = URLSessionConfiguration.ephemeral
        networkConfig.protocolClasses = [VisualWireProtocol.self]
        let network = URLSession(configuration: networkConfig)
        defer { network.invalidateAndCancel() }
        var settings = AppSettings.defaults
        settings.ai.baseURL = "https://synthetic.invalid/v1"; settings.ai.visionModel = "synthetic-vision"
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let preview = ScreenshotSession(image: try XCTUnwrap(bitmap.cgImage), origin: "synthetic", settings: { settings },
            verified: { _, _ in true }, allowed: { true },
            sendVisual: ScreenshotVisualAI.sender(client: { AIClient(connection: $0, session: network) }, apiKey: { _ in "synthetic-test-key" }))
        defer { preview.close() }
        preview.text = "Edited synthetic transcript"
        for action in [ScreenshotAIService.Action.translate, .summarize, .explain] {
            preview.prepareImage(action: action)
            XCTAssertTrue(VisualWireProtocol.recorder.take().isEmpty)
            let png = try XCTUnwrap(preview.visual.request?.png)
            preview.confirmImage()
            for _ in 0..<300 where preview.visual.isBusy { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertEqual(preview.visual.phase, .done)
            XCTAssertEqual(preview.result, "Synthetic visible answer")
            let payload = try XCTUnwrap(VisualWireProtocol.recorder.take().first)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "synthetic-vision")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            let sentText = try XCTUnwrap(content.first { $0["type"] as? String == "text" }?["text"] as? String)
            XCTAssertEqual(sentText, ScreenshotAIService.prompt(action: action, transcript: preview.text))
            let image = try XCTUnwrap(content.first { $0["type"] as? String == "image_url" }?["image_url"] as? [String: Any])
            XCTAssertEqual(image["url"] as? String, "data:image/png;base64," + png.base64EncodedString())
        }
    }
}
