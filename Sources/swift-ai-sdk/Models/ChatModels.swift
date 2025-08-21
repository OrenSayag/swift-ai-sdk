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

struct ActiveResponse {
    var state: StreamingUIMessageState
    var task: URLSessionDataTask? // For abort/cancel
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
