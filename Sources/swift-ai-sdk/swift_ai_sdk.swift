// The Swift Programming Language
// https://docs.swift.org/swift-book

import Combine
import Foundation

public enum ChatError: Error {
    case messageNotFound(id: String)
    case notUserMessage(id: String)
    case invalidLastSessionMessage(id: String)
    case tooManyRecursionAttempts(id: String)
    case invalidTransportConfiguration(id: String)
}

public enum ChatRequestTrigger: String {
    case submitMessage = "submit-message"
    case resumeStream = "resume-stream"
    case regenerateMessage = "regenerate-message"
}

public struct ChatRequestOptions {
    public let headers: [String: String]?
    public let body: [String: Any]?
    public let metadata: [String: Any]?

    public init(
        headers: [String: String]? = nil,
        body: [String: Any]? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.headers = headers
        self.body = body
        self.metadata = metadata
    }
}

public struct MakeRequestInput {
    public let trigger: ChatRequestTrigger
    public let messageId: String?
    public let options: ChatRequestOptions?

    public init(
        trigger: ChatRequestTrigger,
        messageId: String? = nil,
        options: ChatRequestOptions? = nil
    ) {
        self.trigger = trigger
        self.messageId = messageId
        self.options = options
    }
}

public enum UIMessageRole: String {
    case system, user, assistant
}

public protocol MessagePart {
    func asDictionary() -> [String: Any]
}

public enum MessagePartState: String {
    case streaming, done
}

public class TextPart: MessagePart {
    public var text: String
    public var state: MessagePartState?
    public var providerMetadata: Any?

    public init(
        text: String,
        state: MessagePartState? = nil,
        providerMetadata: Any? = nil
    ) {
        self.text = text
        self.state = state
        self.providerMetadata = providerMetadata
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "text": text,
        ]
        if let state = state {
            dict["state"] = state.rawValue
        }
        if let metadata = providerMetadata {
            dict["providerMetadata"] = metadata
        }
        return dict
    }
}

struct ActiveResponse {
    var state: StreamingUIMessageState
    var task: URLSessionDataTask? // For abort/cancel
}

public struct File {
    public let filename: String
    public let url: URL
    public let mediaType: String
}

public struct FilePart: MessagePart {
    public let filename: String
    public let url: URL
    public let mediaType: String
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "filename": filename,
            "url": url.absoluteString,
            "mediaType": mediaType,
        ]
        return dict
    }
}

public class UIMessage {
    public let id: String
    public let role: UIMessageRole
    public var parts: [MessagePart]
    public var metadata: [String: Any]?
    public init(
        id: String, role: UIMessageRole, parts: [MessagePart], metadata: [String: Any]? = nil
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.metadata = metadata
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "role": role.rawValue,
            "parts": parts.map { $0.asDictionary() },
        ]
        if let metadata = metadata {
            dict["metadata"] = metadata
        }
        return dict
    }
}

public enum ChatStatus {
    case submitted
    case streaming
    case ready
    case error
}

public class ChatState {
    @Published public var status: ChatStatus = .ready
    @Published public var error: Error?
    @Published public var messages: [UIMessage] = []

    public func pushMessage(_ message: UIMessage) {
        messages.append(message)
    }

    public func popMessage() {
        _ = messages.popLast()
    }

    public func replaceMessage(at index: Int, with message: UIMessage) {
        messages[index] = message
    }
}

public typealias ChatOnErrorCallback = (Error) -> Void
public typealias ChatOnFinishCallback = (UIMessage) -> Void
public typealias ChatOnToolCallCallback = (Any) -> Void
public typealias ChatOnDataCallback = (Any) -> Void
public typealias SendAutomaticallyWhen = ([UIMessage]) -> Bool

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

public struct ChatInit {
    public var id: String?
    public var state: ChatState
    public var generateId: (() -> String)?
    public var onError: ChatOnErrorCallback?
    public var onFinish: ChatOnFinishCallback?
    public var onToolCall: ChatOnToolCallCallback?
    public var onData: ChatOnDataCallback?
    public var sTextPartendAutomaticallyWhen: SendAutomaticallyWhen?
    public var transport: ChatTransport
    public var sendAutomaticallyWhen: SendAutomaticallyWhen?
    var maxToolCalls: Int

    public init(
        id: String? = nil,
        state: ChatState,
        generateId: (() -> String)? = nil,
        onError: ChatOnErrorCallback? = nil,
        onFinish: ChatOnFinishCallback? = nil,
        onToolCall: ChatOnToolCallCallback? = nil,
        onData: ChatOnDataCallback? = nil,
        sendAutomaticallyWhen: SendAutomaticallyWhen? = nil,
        transport: ChatTransport? = nil,
        defaultChatTransportApiConfig: ChatTransportApiConfig? = nil,
        maxToolCalls: Int = 10
    ) throws {
        self.id = id
        self.state = state
        self.generateId = generateId
        self.onError = onError
        self.onFinish = onFinish
        self.onToolCall = onToolCall
        self.onData = onData
        self.sendAutomaticallyWhen = sendAutomaticallyWhen
        self.maxToolCalls = maxToolCalls
        guard defaultChatTransportApiConfig != nil || transport != nil else {
            throw ChatError.invalidTransportConfiguration(id: id ?? "unknown")
        }
        self.transport =
            transport
                ?? DefaultChatTransport(
                    apiConfig: defaultChatTransportApiConfig!
                )
    }
}

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

                        let replaceLastMessage = activeResponse.state.message.id == self.lastMessage?.id

                        if replaceLastMessage {
                            self.state.replaceMessage(at: self.state.messages.count - 1,
                                                      with: activeResponse.state.message)
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
