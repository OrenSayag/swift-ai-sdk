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

func createTestChatInit() throws -> ChatInit {
    return try ChatInit(
        id: "test-chat",
        transport: CustomChatTransport(
            apiConfig: ChatTransportApiConfig(
                apiBaseUrl: "http://localhost:3001",
                apiChatPath: "/chat/test"
            )
        )
    )
}

@Test func sendMessage() async throws {
    let chat = try Chat(createTestChatInit())
    // let cancellable = chat.state.$messages.sink { messages in
    //     dump(messages)
    // }
    let message = UIMessage(id: "test-message", role: .user, parts: [])
    try await chat.sendMessage(input: .message(message, messageId: nil))
    #expect(chat.state.messages.count == 2, "Message should be added, response should be received")
    #expect(chat.state.messages.first?.id == "test-message", "Should use correct message id")
    #expect(chat.state.messages.first?.role == .user, "Role should be user")
    dump(chat.state.messages)
}

@Test func sendTextAndFilesMessage() async throws {
    let chat = try Chat(createTestChatInit())
    let testFile = File(filename: "300.jpg", url: URL(string: "https://fastly.picsum.photos/id/90/200/300.jpg?hmac=yKaRyhG3EFez3DuYnuPdh29pSCXLc8DDXROYdKQQp30")!, mediaType: "image/jpg")
    try await chat.sendMessage(input: .text("What do you see in the picture?", files: [testFile], metadata: nil, messageId: nil))
    #expect(chat.state.messages.count == 2, "Message and response should be present")
    let message = chat.state.messages.first!
    #expect(message.parts.count == 2, "Message should have file and text part")
    #expect(message.parts[0] is FilePart, "First part should be FilePart")
    #expect(message.parts[1] is TextPart, "Second part should be TextPart")
    dump(chat.state.messages)
}

@Test func sendToolCallMessage() async throws {
    let chat = try Chat(createTestChatInit())

    try await chat.sendMessage(input: .text("what is my nutrition settings?", files: nil, metadata: nil, messageId: nil))

    #expect(chat.state.messages.count == 2, "User message and assistant response should be present")

    // Examine the assistant message for tool parts
    let assistantMessage = chat.state.messages.last!
    #expect(assistantMessage.role == .assistant, "Last message should be from assistant")

    // Check for tool parts in the response
    let toolParts = assistantMessage.parts.compactMap { $0 as? ToolPart }
    let dynamicToolParts = assistantMessage.parts.compactMap { $0 as? DynamicToolPart }

    let totalToolParts = toolParts.count + dynamicToolParts.count
    #expect(totalToolParts > 0, "Assistant message should contain tool parts")

    // Verify tool parts have expected properties
    for toolPart in toolParts {
        #expect(!toolPart.toolName.isEmpty, "Tool part should have a tool name")
        #expect(!toolPart.toolCallId.isEmpty, "Tool part should have a tool call ID")
        #expect(toolPart.state != .inputStreaming, "Tool part should not be in streaming state after completion")
    }

    for dynamicToolPart in dynamicToolParts {
        #expect(!dynamicToolPart.toolName.isEmpty, "Dynamic tool part should have a tool name")
        #expect(!dynamicToolPart.toolCallId.isEmpty, "Dynamic tool part should have a tool call ID")
        #expect(dynamicToolPart.state != .inputStreaming, "Dynamic tool part should not be in streaming state after completion")
    }

    print("Found \(toolParts.count) tool parts and \(dynamicToolParts.count) dynamic tool parts in response")
    dump(chat.state.messages)
}

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
