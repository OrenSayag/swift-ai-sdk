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
    var stream:AsyncStream<UIMessageChunk>
    var runUpdateMessageJob: (_ job: @escaping (_ state: inout StreamingUIMessageState, _ write: () -> Void) -> Void) async -> Void
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

    func processUIMessageStream(options: ProcessUIMessageStreamOptions) -> AsyncStream<UIMessageChunk> {
        guard let stream = options.stream as? AsyncStream<UIMessageChunk> else {
            options.onError(ProcessUIMessageStreamError.invalidStreamType)
            return AsyncStream { $0.finish() }
        }

        return AsyncStream { continuation in
            Task {
                do {
                    for await chunk in stream {
                        await options.runUpdateMessageJob { state, write in
                            switch chunk {
                            case let .textStart(id, _):
                                // Update state.activeTextParts, append to state's message.parts, etc
                                state.activeTextParts[id] = TextPart(text: "", state: .streaming)
                                state.message.parts.append(state.activeTextParts[id]!)
                                write()
                            case let .textDelta(id, delta, _):
                                if var textPart = state.activeTextParts[id] as? TextPart,
                                   let existingText = textPart.text as? String
                                {
                                    textPart.text = existingText + delta
                                    state.activeTextParts[id] = textPart
                                }
                                write()
                            case let .textEnd(id, _):
                                if var textPart = state.activeTextParts[id] as? TextPart {
                                    textPart.state = .done
                                    state.activeTextParts[id] = textPart
                                }
                                state.activeTextParts.removeValue(forKey: id)
                                write()
                            case .reasoningStart, .reasoningDelta, .reasoningEnd:
                                // Extend with similar logic for reasoning parts
                                write()
                            case .toolInputAvailable, .toolInputError:
                                options.onToolCall?(chunk)
                                write()
                            case .dataChunk:
                                options.onData?(chunk)
                                write()
                            case let .error(errorText):
                                options.onError(NSError(domain: "Chat", code: 0, userInfo: [NSLocalizedDescriptionKey: errorText]))
                            default:
                                write()
                            }
                        }
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
