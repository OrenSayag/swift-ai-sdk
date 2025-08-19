
import Foundation

public protocol ChatTransport {
    func sendMessages(
        chatId: String,
        messages: [UIMessage],
        abortSignal: Task<Void, Never>?,
        metadata: [String: Any]?,
        headers: [String: String]?,
        body: [String: Any]?,
        trigger: ChatRequestTrigger,
        messageId: String?
    ) async throws -> AsyncStream<UIMessageChunk>

    func reconnectToStream(
        chatId: String,
        metadata: [String: Any]?,
        headers: [String: String]?,
        body: [String: Any]?
    ) async throws -> AsyncStream<UIMessageChunk>?
}

public class DefaultChatTransport: ChatTransport {
    public let api: String
    public let session: URLSession

    public init(api: String = "/api/chat", session: URLSession = .shared) {
        self.api = api
        self.session = session
    }

    public func sendMessages(
        chatId: String,
        messages: [UIMessage],
        abortSignal _: Task<Void, Never>? = nil,
        metadata: [String: Any]? = nil,
        headers: [String: String]? = nil,
        body: [String: Any]? = nil,
        trigger: ChatRequestTrigger,
        messageId: String?
    ) async throws -> AsyncStream<UIMessageChunk> {
        // Build the POST request body
        var requestBody: [String: Any] = [
            "id": chatId,
            "messages": messages.map { $0.asDictionary() },
            "trigger": trigger.rawValue,
        ]
        if let messageId = messageId { requestBody["messageId"] = messageId }
        if let meta = metadata { requestBody["metadata"] = meta }
        if let body = body {
            requestBody.merge(body) { existingValue, _ in existingValue }
        }

        var request = URLRequest(url: URL(string: api)!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers?.forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }

        return try await processResponseStream(request: request)
    }

    public func reconnectToStream(
        chatId: String,
        metadata _: [String: Any]? = nil,
        headers: [String: String]? = nil,
        body _: [String: Any]? = nil
    ) async throws -> AsyncStream<UIMessageChunk>? {
        // Typical reconnect endpoint: /api/chat/{chatId}/stream
        var url = URL(string: api)!
        url.appendPathComponent(chatId)
        url.appendPathComponent("stream")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        headers?.forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }

        let (response, responseStream) = try await streamURL(request: request)

        guard let httpResp = response as? HTTPURLResponse else { throw NSError(domain: "Chat", code: 1002) }
        if httpResp.statusCode == 204 { return nil }
        guard (200 ..< 300).contains(httpResp.statusCode) else {
            throw NSError(domain: "Chat", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch the chat response"])
        }
        guard let inputStream = responseStream else {
            throw NSError(domain: "Chat", code: 1003, userInfo: [NSLocalizedDescriptionKey: "The response body is empty"])
        }
        return parseEventStream(inputStream: inputStream)
    }

    // MARK: - Helpers

    private func processResponseStream(request: URLRequest) async throws -> AsyncStream<UIMessageChunk> {
        let (response, inputStream) = try await streamURL(request: request)
        guard let httpResp = response as? HTTPURLResponse else { throw NSError(domain: "Chat", code: 1002) }
        guard (200 ..< 300).contains(httpResp.statusCode) else {
            throw NSError(domain: "Chat", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch the chat response"])
        }
        guard let inputStream = inputStream else {
            throw NSError(domain: "Chat", code: 1003, userInfo: [NSLocalizedDescriptionKey: "The response body is empty"])
        }
        return parseEventStream(inputStream: inputStream)
    }

    private func streamURL(request: URLRequest) async throws -> (URLResponse, InputStream?) {
        // This assumes you use a custom streaming function or library,
        // because standard URLSession doesn't support full streaming in simple API.
        // If using URLSession's bytes(for:...), this needs to be changed to AsyncStream<Data>
        let (data, response) = try await session.data(for: request) // Demo only; real streaming requires more
        let stream = InputStream(data: data)
        return (response, stream)
    }

    private func parseEventStream(inputStream: InputStream) -> AsyncStream<UIMessageChunk> {
        // This should parse your actual EventStream or NDJSON to chunks.
        return AsyncStream { continuation in
            inputStream.open()
            defer { inputStream.close() }
            let bufferSize = 4096
            var buffer = Data()
            var temp = [UInt8](repeating: 0, count: bufferSize)

            while inputStream.hasBytesAvailable {
                let read = inputStream.read(&temp, maxLength: bufferSize)
                if read > 0 {
                    buffer.append(contentsOf: temp[0 ..< read])
                    // Assume each JSON object is newline-separated; adjust parsing as needed
                    while let range = buffer.range(of: Data([0x0A])) { // Newline
                        let line = buffer[..<range.lowerBound]
                        buffer = buffer[(range.upperBound)...]
                        if let json = try? JSONSerialization.jsonObject(with: line),
                           let chunk = UIMessageChunk.from(json: json)
                        { // Implement this
                            continuation.yield(chunk)
                        }
                    }
                } else {
                    break
                }
            }
            continuation.finish()
        }
    }
}
