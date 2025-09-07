# Swift AI SDK

Swift package for consuming AI chat streams from a Vercel AI SDK v5 backend.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/your-username/swift-ai-sdk.git", from: "1.0.0")
]
```

## Usage

```swift
import swift_ai_sdk
import Combine

class ChatManager: ObservableObject {
    @Published var messages: [UIMessage] = []
    @Published var status: ChatStatus = .ready
    
    private var chat: Chat?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupChat()
    }
    
    private func setupChat() {
        let apiConfig = ChatTransportApiConfig(
            apiBaseUrl: "https://your-api.com",
            apiChatPath: "/chat"
        )
        
        let chatInit = try! ChatInit(
            onFinish: { [weak self] message in
                DispatchQueue.main.async {
                    self?.messages.append(message)
                }
            },
            defaultChatTransportApiConfig: apiConfig
        )
        
        chat = Chat(chatInit)
        
        // Observe messages
        chat?.state.$messages
            .receive(on: DispatchQueue.main)
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)
    }
    
    func sendMessage(_ text: String) async {
        try? await chat?.sendMessage(
            input: .text(text, files: nil, metadata: nil, messageId: nil)
        )
    }
}
```

## SwiftUI

```swift
struct ChatView: View {
    @StateObject private var chatManager = ChatManager()
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(chatManager.messages, id: \.id) { message in
                    Text(message.parts.first?.text ?? "")
                        .padding()
                }
            }
            
            HStack {
                TextField("Message", text: $messageText)
                Button("Send") {
                    Task { await chatManager.sendMessage(messageText) }
                    messageText = ""
                }
            }
        }
    }
}
```

## Custom Transport

```swift
class AuthenticatedTransport: DefaultChatTransport {
    override func sendMessages(/* ... */) async throws -> AsyncStream<UIMessageChunk> {
        var headers = headers ?? [:]
        headers["Authorization"] = "Bearer \(token)"
        return try await super.sendMessages(/* ... */)
    }
}
```
