public struct ChatTransportApiConfig {
    public let apiBaseUrl: String
    public let apiChatPath: String
    public let apiReconnectToStreamPath: String?
    public init(
        apiBaseUrl: String,
        apiChatPath: String,
        apiReconnectToStreamPath: String? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.apiChatPath = apiChatPath
        self.apiReconnectToStreamPath = apiReconnectToStreamPath
    }
}

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
        body: [String: Any]?,
        path: String?
    ) async throws -> AsyncStream<UIMessageChunk>?
}
