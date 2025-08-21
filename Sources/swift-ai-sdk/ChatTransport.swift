import Foundation

public class DefaultChatTransport: ChatTransport {
    public let apiConfig: ChatTransportApiConfig
    public let session: URLSession

    public init(apiConfig: ChatTransportApiConfig, session: URLSession = .shared) {
        self.session = session
        self.apiConfig = apiConfig
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

        var url = URL(string: apiConfig.apiBaseUrl)!
        url.appendPathComponent(apiConfig.apiChatPath)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers?.forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }

        return try await processResponseStream(request: request)
    }

    public func reconnectToStream(
        chatId _: String,
        metadata _: [String: Any]? = nil,
        headers: [String: String]? = nil,
        body _: [String: Any]? = nil,
        path: String? = nil
    ) async throws -> AsyncStream<UIMessageChunk>? {
        var url = URL(string: apiConfig.apiBaseUrl)!
        guard let realpath = path ?? apiConfig.apiReconnectToStreamPath else {
            throw NSError(
                domain: "Chat", code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Reconnect path is not set"]
            )
        }
        url.appendPathComponent(realpath)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        headers?.forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }
        let (response, bytes) = try await streamURL(request: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw NSError(domain: "Chat", code: 1002)
        }
        if httpResp.statusCode == 204 { return nil }
        guard (200 ..< 300).contains(httpResp.statusCode) else {
            throw NSError(
                domain: "Chat", code: httpResp.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch the chat response"]
            )
        }
        return parseEventStream(bytes: bytes)
    }

    // MARK: - Helpers

    private func processResponseStream(request: URLRequest) async throws -> AsyncStream<
        UIMessageChunk
    > {
        let (response, bytes) = try await streamURL(request: request)
        guard let httpResp = response as? HTTPURLResponse, (200 ..< 300).contains(httpResp.statusCode)
        else {
            throw NSError(domain: "Chat", code: 1002)
        }
        return parseEventStream(bytes: bytes)
    }

    private func streamURL(request: URLRequest) async throws -> (URLResponse, URLSession.AsyncBytes) {
        let (bytes, response) = try await session.bytes(for: request)
        return (response, bytes)
    }

    private func parseEventStream(bytes: URLSession.AsyncBytes) -> AsyncStream<UIMessageChunk> {
        AsyncStream { continuation in
            Task {
                do {
                    var buffer = ""
                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }

                        if line.hasPrefix("data: ") {
                            let dataContent = String(line.dropFirst(6)) // Remove "data: " prefix

                            if dataContent == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            if let data = dataContent.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data),
                               let chunk = UIMessageChunk.from(json: json)
                            {
                                continuation.yield(chunk)
                            } else {
                                print("Failed to parse chunk from data: '\(dataContent)'")
                            }
                        }
                    }
                } catch {
                    print("Error parsing event stream: \(error)")
                }
                continuation.finish()
            }
        }
    }
}
