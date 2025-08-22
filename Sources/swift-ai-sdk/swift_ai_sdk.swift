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
        return files.map { FilePart(filename: $0.filename, url: $0.url.absoluteString, mediaType: $0.mediaType) }
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

    var autoSendRecursionCount = 0

    public var lastMessage: UIMessage? {
        return state.messages.last
    }

    public var messages: [UIMessage] {
        get { state.messages }
        set { state.messages = newValue }
    }
}
