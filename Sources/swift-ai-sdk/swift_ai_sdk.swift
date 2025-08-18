// The Swift Programming Language
// https://docs.swift.org/swift-book

public class UIMessage {
    var id: String
    var role: String
    public init(id: String, role: String) {
        self.id = id
        self.role = role
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

public class Chat {
    public let id: String
    public var state: ChatState

    public init(id: String, state: ChatState) {
        self.id = id
        self.state = state
    }

    public func sendMessage(_ message: UIMessage?) async {
        guard let message = message else {
            return
        }
        state.pushMessage(message)
    }
}
