import Foundation
@testable import swift_ai_sdk
import Testing

@Test func sendMessage() async throws {
    let mockState = ChatState()
    let chat = Chat(ChatInit(id: "test-chat", state: mockState))
    let message = UIMessage(id: "test-message", role: .user, parts: [])
    try await chat.sendMessage(input: .message(message, messageId: nil))
    #expect(chat.state.messages.count == 1)
    #expect(chat.state.messages.first?.id == "test-message")
}

@Test func sendTextAndFilesMessage() async throws {
    let mockState = ChatState()
    let chat = Chat(ChatInit(id: "test-chat", state: mockState))
    let testFile = File(filename: "a.txt", url: URL(string: "file:///a.txt")!, mediaType: "text/plain")
    try await chat.sendMessage(input: .text("hi", files: [testFile], metadata: nil, messageId: nil))
    #expect(chat.state.messages.count == 1)
    #expect(chat.state.messages.first?.parts.count == 2)
    #expect(chat.state.messages.first?.parts[0] is FilePart)
    #expect(chat.state.messages.first?.parts[1] is TextPart)
}
