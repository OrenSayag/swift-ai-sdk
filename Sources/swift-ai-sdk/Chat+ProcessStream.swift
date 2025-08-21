import Foundation

public struct StreamingUIMessageState: @unchecked Sendable {
    public var message: UIMessage
    public var activeTextParts: [String: TextPart]
    public var activeReasoningParts: [String: MessagePart]
    public var partialToolCalls: [String: MessagePart]

    public init(
        message: UIMessage,
        activeTextParts: [String: TextPart] = [:],
        activeReasoningParts: [String: MessagePart] = [:],
        partialToolCalls: [String: MessagePart] = [:]
    ) {
        self.message = message
        self.activeTextParts = activeTextParts
        self.activeReasoningParts = activeReasoningParts
        self.partialToolCalls = partialToolCalls
    }
}

public struct ProcessUIMessageStreamOptions: @unchecked Sendable {
    var stream: AsyncStream<UIMessageChunk>
    var runUpdateMessageJob: (_ chunk: UIMessageChunk) async -> Void
    var onError: (Error) -> Void
    var onToolCall: ((Any) -> Void)?
    var onData: ((Any) -> Void)?
}

enum ProcessUIMessageStreamError: Error {
    case invalidStreamType
}

extension Chat {
    public func createStreamingUIMessageState(
        lastMessage: UIMessage?,
        messageId: String
    ) -> StreamingUIMessageState {
        if let last = lastMessage, last.role == .assistant {
            return StreamingUIMessageState(message: last)
        } else {
            let assistantMessage = UIMessage(
                id: messageId,
                role: .assistant,
                parts: [],
            )
            return StreamingUIMessageState(message: assistantMessage)
        }
    }

    func processUIMessageStream(options: ProcessUIMessageStreamOptions) -> AsyncStream<
        UIMessageChunk
    > {
        guard let stream = options.stream as? AsyncStream<UIMessageChunk> else {
            options.onError(ProcessUIMessageStreamError.invalidStreamType)
            return AsyncStream { $0.finish() }
        }

        return AsyncStream { continuation in
            Task {
                do {
                    for await chunk in stream {
                        // Process the chunk and update the state
                        await options.runUpdateMessageJob(chunk)
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    options.onError(error)
                    continuation.finish()
                }
            }
        }
    }
}
