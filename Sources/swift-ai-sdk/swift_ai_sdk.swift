// The Swift Programming Language
// https://docs.swift.org/swift-book

import Combine
import Foundation

public class Chat {
    public let id: String
    public var state: ChatState
    public let generateId: () -> String
    public let onError: ChatOnErrorCallback?
    public let onFinish: ChatOnFinishCallback?
    public let onToolCall: ChatOnToolCallCallback?
    public let onData: ChatOnDataCallback?
    public let sendAutomaticallyWhen: SendAutomaticallyWhen?
    public let transport: ChatTransport
    let maxToolCalls: Int

    public init(_ initStruct: ChatInit) {
        generateId = initStruct.generateId ?? { UUID().uuidString }
        id = initStruct.id ?? generateId()
        state = initStruct.state
        onError = initStruct.onError
        onFinish = initStruct.onFinish
        onToolCall = initStruct.onToolCall
        onData = initStruct.onData
        sendAutomaticallyWhen = initStruct.sendAutomaticallyWhen
        transport = initStruct.transport
        maxToolCalls = initStruct.maxToolCalls
    }

    public enum SendMessageInput {
        case message(UIMessage, messageId: String?)
        case text(String, files: [File]?, metadata: [String: Any]?, messageId: String?)
        case files([File], metadata: [String: Any]?, messageId: String?)
        case none
    }

    // MARK: - Status/Error Management

    public var status: ChatStatus {
        return state.status
    }

    public var error: Error? {
        return state.error
    }

    public func setStatus(status: ChatStatus, error: Error? = nil) {
        guard state.status != status else { return }
        state.status = status
        state.error = error
    }

    public func clearError() {
        if state.status == .error {
            state.error = nil
            setStatus(status: .ready)
        }
    }

    // MARK: - Messaging

    private func convertFilesToParts(_ files: [File]?) -> [FilePart] {
        guard let files = files else { return [] }
        return files.map { FilePart(filename: $0.filename, url: $0.url, mediaType: $0.mediaType) }
    }

    public func sendMessage(
        input: SendMessageInput,
        options: ChatRequestOptions? = nil
    ) async throws {
        switch input {
        case .none:
            try await makeRequest(
                input: MakeRequestInput(
                    trigger: .submitMessage,
                    messageId: lastMessage?.id,
                    options: options
                ))
            return

        case let .message(msg, messageId):
            if let messageId = messageId {
                guard let idx = messages.firstIndex(where: { $0.id == messageId }) else {
                    throw ChatError.messageNotFound(id: messageId)
                }
                guard messages[idx].role == .user else {
                    throw ChatError.notUserMessage(id: messageId)
                }
                messages = Array(messages.prefix(upTo: idx + 1))
                state.replaceMessage(at: idx, with: msg)
            } else {
                state.pushMessage(msg)
            }
            try await makeRequest(
                input: MakeRequestInput(
                    trigger: .submitMessage,
                    messageId: messageId,
                    options: options
                ))
            return

        case let .text(text, files, metadata, messageId):
            let fileParts = convertFilesToParts(files)
            let textPart = TextPart(text: text)
            let combinedParts: [MessagePart] = fileParts + [textPart]
            let newMsg = UIMessage(
                id: messageId ?? generateId(),
                role: .user,
                parts: combinedParts,
                metadata: metadata
            )
            if let messageId = messageId {
                guard let idx = messages.firstIndex(where: { $0.id == messageId }) else {
                    throw ChatError.messageNotFound(id: messageId)
                }
                guard messages[idx].role == .user else {
                    throw ChatError.notUserMessage(id: messageId)
                }
                messages = Array(messages.prefix(upTo: idx + 1))
                state.replaceMessage(at: idx, with: newMsg)
            } else {
                state.pushMessage(newMsg)
            }
            try await makeRequest(
                input: MakeRequestInput(
                    trigger: .submitMessage,
                    messageId: messageId,
                    options: options
                ))
            return

        case let .files(files, metadata, messageId):
            let fileParts = convertFilesToParts(files)
            let newMsg = UIMessage(
                id: messageId ?? generateId(),
                role: .user,
                parts: fileParts,
                metadata: metadata
            )
            if let messageId = messageId {
                guard let idx = messages.firstIndex(where: { $0.id == messageId }) else {
                    throw ChatError.messageNotFound(id: messageId)
                }
                guard messages[idx].role == .user else {
                    throw ChatError.notUserMessage(id: messageId)
                }
                messages = Array(messages.prefix(upTo: idx + 1))
                state.replaceMessage(at: idx, with: newMsg)
            } else {
                state.pushMessage(newMsg)
            }
            try await makeRequest(
                input: MakeRequestInput(
                    trigger: .submitMessage,
                    messageId: messageId,
                    options: options
                ))
            return
        }
    }

    var activeResponse: ActiveResponse?

    private static let messageJobQueue = DispatchQueue(
        label: "chat.message.job.queue", qos: .userInitiated
    )

    func runUpdateMessageJob(
        job: @escaping @Sendable (_ state: StreamingUIMessageState, _ write: @escaping () -> Void)
        async -> Void,
        state: StreamingUIMessageState,
        write: @escaping @Sendable () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "chat.message.job.queue").async {
                Task {
                    await job(state, write)
                    continuation.resume()
                }
            }
        }
    }

    private var autoSendRecursionCount = 0

    public func makeRequest(input: MakeRequestInput) async throws {
        setStatus(status: .submitted, error: nil)

        let streamingState = createStreamingUIMessageState(
            lastMessage: lastMessage,
            messageId: generateId()
        )

        // TODO: implement task fpr aborting/canceling the request
        activeResponse = ActiveResponse(state: streamingState, task: nil)

        var stream: AsyncStream<UIMessageChunk>

        do {
            defer {
                activeResponse = nil
            }
            if input.trigger == .resumeStream {
                guard
                    let reconnectStream = try await transport.reconnectToStream(
                        chatId: id,
                        metadata: input.options?.metadata,
                        headers: input.options?.headers,
                        body: input.options?.body,
                        path: nil
                    )
                else {
                    setStatus(status: .ready)
                    // No active stream to resume
                    return
                }
                stream = reconnectStream
            } else {
                stream = try await transport.sendMessages(
                    chatId: id,
                    messages: messages,
                    abortSignal: nil,
                    metadata: input.options?.metadata,
                    headers: input.options?.headers,
                    body: input.options?.body,
                    trigger: input.trigger,
                    messageId: input.messageId
                )
            }

            var thrownError: Error?
            let asyncStream = processUIMessageStream(
                options: ProcessUIMessageStreamOptions(
                    stream: stream,
                    runUpdateMessageJob: { chunk in
                        self.setStatus(status: .streaming)

                        guard var activeResponse = self.activeResponse else { return }

                        switch chunk {
                        case let .textStart(id, _):
                            activeResponse.state.activeTextParts[id] = TextPart(
                                text: "", state: .streaming
                            )
                            activeResponse.state.message.parts.append(
                                activeResponse.state.activeTextParts[id]!)
                        case let .textDelta(id, delta, _):
                            if var textPart = activeResponse.state.activeTextParts[id] as? TextPart,
                               let existingText = textPart.text as? String
                            {
                                textPart.text = existingText + delta
                                activeResponse.state.activeTextParts[id] = textPart
                            }
                        case let .textEnd(id, _):
                            if var textPart = activeResponse.state.activeTextParts[id] as? TextPart {
                                textPart.state = .done
                                activeResponse.state.activeTextParts[id] = textPart
                            }
                            activeResponse.state.activeTextParts.removeValue(forKey: id)
                        case .reasoningStart, .reasoningDelta, .reasoningEnd:
                            // Extend with similar logic for reasoning parts
                            break
                        case .toolInputAvailable, .toolInputError:
                            self.onToolCall?(chunk)
                        case .dataChunk:
                            self.onData?(chunk)
                        case let .error(errorText):
                            self.onError?(
                                NSError(
                                    domain: "Chat", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: errorText]
                                ))
                        default:
                            break
                        }

                        self.activeResponse = activeResponse

                        let replaceLastMessage =
                            activeResponse.state.message.id == self.lastMessage?.id

                        if replaceLastMessage {
                            self.state.replaceMessage(
                                at: self.state.messages.count - 1,
                                with: activeResponse.state.message
                            )
                        } else {
                            self.state.pushMessage(activeResponse.state.message)
                        }
                    },
                    onError: { error in
                        thrownError = error
                        self.onError?(error)
                    },
                    onToolCall: { toolCall in
                        self.onToolCall?(toolCall)
                    },
                    onData: { data in
                        self.onData?(data)
                    }
                )
            )

            for await _ in asyncStream {
                // The stream processing is handled in processUIMessageStream
            }

            if let thrownError {
                throw thrownError
            }

            guard let lastSessionMessage = activeResponse?.state.message ?? lastMessage else {
                throw ChatError.invalidLastSessionMessage(id: input.messageId ?? "unknown")
            }
            onFinish?(lastSessionMessage)
            setStatus(status: .ready)

        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSUserCancelledError
            {
                setStatus(status: .ready)
            } else {
                onError?(error)
                setStatus(status: .error, error: error)
            }
            throw error
        }
        if let sendAuto = sendAutomaticallyWhen, sendAuto(state.messages) {
            guard autoSendRecursionCount < maxToolCalls else {
                throw ChatError.tooManyRecursionAttempts(id: input.messageId ?? "unknown")
            }
            autoSendRecursionCount += 1
            defer { autoSendRecursionCount -= 1 }
            try await makeRequest(
                input: MakeRequestInput(
                    trigger: .submitMessage,
                    messageId: lastMessage?.id,
                    options: input.options
                ))
        }
    }

    public var lastMessage: UIMessage? {
        return state.messages.last
    }

    public var messages: [UIMessage] {
        get { state.messages }
        set { state.messages = newValue }
    }
}
