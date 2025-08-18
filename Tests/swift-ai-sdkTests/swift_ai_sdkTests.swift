@testable import swift_ai_sdk
import Testing

@Test func sendMessage() async throws {
    let mockState = ChatState()
    let chat = Chat(id: "test-chat", state: mockState)
    let message = UIMessage(id: "test-message", role: "user")
    await chat.sendMessage(message)
    #expect(chat.state.messages.count == 1)
    #expect(chat.state.messages.first?.id == "test-message")
}
