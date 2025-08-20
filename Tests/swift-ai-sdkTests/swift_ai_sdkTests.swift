import Foundation
@testable import swift_ai_sdk
import Testing

public class CustomChatTransport: DefaultChatTransport {
    override public func sendMessages(
        chatId: String,
        messages: [UIMessage],
        abortSignal: Task<Void, Never>? = nil,
        metadata: [String: Any]? = nil,
        headers customHeaders: [String: String]? = nil,
        body _: [String: Any]? = nil,
        trigger: ChatRequestTrigger,
        messageId: String? = nil
    ) async throws -> AsyncStream<UIMessageChunk> {
        let requestBody = [
            "timezone": TimeZone.current.identifier,
            "chatType": "app",
        ]

        return try await super.sendMessages(
            chatId: chatId,
            messages: messages,
            abortSignal: abortSignal,
            metadata: metadata,
            headers: customHeaders,
            body: requestBody,
            trigger: trigger,
            messageId: messageId
        )
    }
}

@Test func sendMessage() async throws {
    let mockState = ChatState()
    let chatInit = try ChatInit(
        id: "test-chat",
        state: mockState,
        transport: CustomChatTransport(
            apiConfig: ChatTransportApiConfig(
                apiBaseUrl: "http://localhost:3001",
                apiChatPath: "/chat/test"
            )
        )
    )
    let chat = Chat(chatInit)
    let message = UIMessage(id: "test-message", role: .user, parts: [])
    try await chat.sendMessage(input: .message(message, messageId: nil))
    #expect(chat.state.messages.count == 1, "Message should be added")
    #expect(chat.state.messages.first?.id == "test-message", "Should use correct message id")
    #expect(chat.state.messages.first?.role == .user, "Role should be user")
    dump(chat.state.messages)
}

// @Test func sendTextAndFilesMessage() async throws {
//     let mockState = ChatState()
//     let chat = Chat(ChatInit(id: "test-chat", state: mockState))
//     let testFile = File(filename: "a.txt", url: URL(string: "file:///a.txt")!, mediaType: "text/plain")
//     try await chat.sendMessage(input: .text("hi", files: [testFile], metadata: nil, messageId: nil))
//     #expect(chat.state.messages.count == 1, "One message should be present")
//     let message = chat.state.messages.first!
//     #expect(message.parts.count == 2, "Message should have file and text part")
//     #expect(message.parts[0] is FilePart, "First part should be FilePart")
//     #expect(message.parts[1] is TextPart, "Second part should be TextPart")
//     dump(chat.state.messages)
// }

// @Test func sendAutomaticallyWhen_noInfiniteRecursion() async throws {
//     let mockState = ChatState()
//     var recursionCount = 0
//     let chat = Chat(ChatInit(
//         id: "recursive-chat",
//         state: mockState,
//         sendAutomaticallyWhen: { _ in
//             recursionCount += 1
//             return recursionCount < 10 // If recursionLimit is 3, inner call will be prevented
//         }
//     ))
//     let message = UIMessage(id: "rec-message", role: .user, parts: [])
//     try await chat.sendMessage(input: .message(message, messageId: nil))
//     #expect(recursionCount <= 3, "Recursion should be limited/prevented")
// }
