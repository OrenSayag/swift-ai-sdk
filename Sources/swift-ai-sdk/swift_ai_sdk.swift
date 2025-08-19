// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

public enum ChatError: Error {
    case messageNotFound(id: String)
    case notUserMessage(id: String)
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

public protocol MessagePart {}
public struct TextPart: MessagePart {
    public let text: String
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
}

public class UIMessage {
    public let id: String
    public let role: UIMessageRole
    public var parts: [MessagePart]
    public var metadata: [String: Any]?
    public init(id: String, role: UIMessageRole, parts: [MessagePart], metadata: [String: Any]? = nil) {
        self.id = id
        self.role = role
        self.parts = parts
        self.metadata = metadata
    }
}

public enum ChatStatus {
    case submitted
    case streaming
    case ready
    case error
}

public class ChatState {
    public var status: ChatStatus = .ready
    public var error: Error?
    public var messages: [UIMessage] = []

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

public struct ChatInit {
    public var id: String?
    public var state: ChatState
    public var generateId: (() -> String)?
    public var onError: ChatOnErrorCallback?
    public var onFinish: ChatOnFinishCallback?
    public var onToolCall: ChatOnToolCallCallback?
    public var onData: ChatOnDataCallback?
    public var sendAutomaticallyWhen: SendAutomaticallyWhen?

    public init(
        id: String? = nil,
        state: ChatState,
        generateId: (() -> String)? = nil,
        onError: ChatOnErrorCallback? = nil,
        onFinish: ChatOnFinishCallback? = nil,
        onToolCall: ChatOnToolCallCallback? = nil,
        onData: ChatOnDataCallback? = nil,
        sendAutomaticallyWhen: SendAutomaticallyWhen? = nil
    ) {
        self.id = id
        self.state = state
        self.generateId = generateId
        self.onError = onError
        self.onFinish = onFinish
        self.onToolCall = onToolCall
        self.onData = onData
        self.sendAutomaticallyWhen = sendAutomaticallyWhen
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

    public init(_ initStruct: ChatInit) {
        generateId = initStruct.generateId ?? { UUID().uuidString }
        id = initStruct.id ?? generateId()
        state = initStruct.state
        onError = initStruct.onError
        onFinish = initStruct.onFinish
        onToolCall = initStruct.onToolCall
        onData = initStruct.onData
        sendAutomaticallyWhen = initStruct.sendAutomaticallyWhen
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
            try await makeRequest(input: MakeRequestInput(
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
            try await makeRequest(input: MakeRequestInput(
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
            try await makeRequest(input: MakeRequestInput(
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
            try await makeRequest(input: MakeRequestInput(
                trigger: .submitMessage,
                messageId: messageId,
                options: options
            ))
            return
        }
    }

    // Placeholders for networking and utilities

    public func makeRequest(input _: MakeRequestInput) async throws {
        print("not implemented: makeRequest")
        // fatalError("makeRequest not implemented")
    }

    public var lastMessage: UIMessage? {
        return state.messages.last
    }

    public var messages: [UIMessage] {
        get { state.messages }
        set { state.messages = newValue }
    }
}
