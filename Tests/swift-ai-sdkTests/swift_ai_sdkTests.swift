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

@Test func testLastAssistantMessageIsCompleteWithToolCalls() async throws {
    let chat = try Chat(createTestChatInit())

    // Send initial message that should trigger tool calls
    try await chat.sendMessage(input: .text("what is my nutrition settings?", files: nil, metadata: nil, messageId: nil))

    #expect(chat.state.messages.count == 2, "Should have user message and assistant response")

    // Test the utility function
    let isComplete = lastAssistantMessageIsCompleteWithToolCalls(messages: chat.state.messages)

    // Verify the last message is from assistant
    let lastMessage = chat.state.messages.last!
    #expect(lastMessage.role == .assistant, "Last message should be from assistant")

    // Check if tool calls are complete using instance method
    let isCompleteInstance = lastMessage.isCompleteWithToolCalls()
    #expect(isComplete == isCompleteInstance, "Both methods should return the same result")

    // If there are tool parts, verify the completion logic
    let toolParts = lastMessage.parts.compactMap { $0 as? ToolPart }
    let dynamicToolParts = lastMessage.parts.compactMap { $0 as? DynamicToolPart }
    let hasToolParts = !toolParts.isEmpty || !dynamicToolParts.isEmpty

    if hasToolParts {
        #expect(isComplete, "Message with tool parts should be complete after processing")

        // Verify all tool parts are in correct final state
        for toolPart in toolParts {
            #expect(toolPart.state == .outputAvailable, "Tool part should be in outputAvailable state")
        }

        for dynamicToolPart in dynamicToolParts {
            #expect(dynamicToolPart.state == .outputAvailable, "Dynamic tool part should be in outputAvailable state")
        }
    } else {
        #expect(!isComplete, "Message without tool parts should not be considered complete with tool calls")
    }

    print("Tool calls complete: \(isComplete)")
    print("Found \(toolParts.count) tool parts, \(dynamicToolParts.count) dynamic tool parts")
}

@Test func autoResendWithToolCallCompletion() async throws {
    let chatInit = try ChatInit(
        id: "test-chat",
        sendAutomaticallyWhen: lastAssistantMessageIsCompleteWithToolCalls,
        transport: CustomChatTransport(
            apiConfig: ChatTransportApiConfig(
                apiBaseUrl: "http://localhost:3001",
                apiChatPath: "/chat/test"
            )
        ),
    )

    let chat = Chat(chatInit)

    try await chat.sendMessage(input: .text("what is my nutrition settings?", files: nil, metadata: nil, messageId: nil))

    print("Total messages after auto-send: \(chat.state.messages.count)")

    let assistantMessages = chat.state.messages.filter { $0.role == .assistant }

    if assistantMessages.count > 1 {
        print("Auto-send was triggered (\(assistantMessages.count) assistant messages)")

        let secondToLastAssistant = assistantMessages[assistantMessages.count - 2]
        let hasToolParts = secondToLastAssistant.parts.contains { part in
            part.isToolPart() || part.isDynamicToolPart()
        }
        #expect(hasToolParts, "Second-to-last assistant message should contain tool parts")

        let lastAssistant = assistantMessages.last!
        let hasOnlyToolParts = !lastAssistant.parts.isEmpty && lastAssistant.parts.allSatisfy { part in
            part.isToolPart() || part.isDynamicToolPart()
        }
        #expect(!hasOnlyToolParts, "Last assistant message should not be only tool parts (should be response after tool execution)")

    } else {
        print("Auto-send was not triggered (only 1 assistant message)")
        #expect(assistantMessages.count == 1, "Should have exactly 1 assistant message if no auto-send")
    }

    dump(chat.state.messages)
}
