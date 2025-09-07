# Swift AI SDK

Swift package for consuming AI chat streams from a [Vercel AI SDK](https://ai-sdk.dev/) v5 backend.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/OrenSayag/swift-ai-sdk.git", from: "1.0.0")
]
```

## Basic Usage

```swift
import Combine
import swift_ai_sdk
import SwiftUI

class ChatManager: ObservableObject {
    static let shared = ChatManager()
    
    private var chat: Chat?
    @Published var prompt = ""
    var currentTask: Task<Void, Never>?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupChat()
    }
    
    private func setupChat() {
        let apiConfig = ChatTransportApiConfig(
            apiBaseUrl: "https://your-api.com",
            apiChatPath: "/chat"
        )
        
        let chatInit = try! ChatInit(
            onError: { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            },
            onFinish: { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            },
            defaultChatTransportApiConfig: apiConfig
        )
        
        chat = Chat(chatInit)
        observeSDKState()
    }
    
    private func observeSDKState() {
        guard let chat = chat else { return }
        
        Task {
            for await _ in chat.state.$messages.values {
                await MainActor.run {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    func generate() async {
        guard let chat = chat else { return }
        
        stopGeneration()
        let text = prompt
        prompt = ""
        
        currentTask = Task {
            try? await chat.sendMessage(
                input: .text(text, files: nil, metadata: nil, messageId: nil)
            )
        }
    }
    
    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

## Custom Transport with Auth

```swift
class CustomChatTransport: DefaultChatTransport {
    override func sendMessages(
        chatId: String,
        messages: [UIMessage],
        abortSignal: Task<Void, Never>? = nil,
        metadata: [String: Any]? = nil,
        headers: [String: String]? = nil,
        body _: [String: Any]? = nil,
        trigger: ChatRequestTrigger,
        messageId: String? = nil
    ) async throws -> AsyncStream<UIMessageChunk> {
        let requestBody = [
            "timezone": TimeZone.current.identifier,
            "chatType": "app"
        ]
        
        let token = "your-auth-token"
        var mergedHeaders = headers ?? [:]
        mergedHeaders["Authorization"] = "Bearer \(token)"
        
        return try await super.sendMessages(
            chatId: chatId,
            messages: messages,
            abortSignal: abortSignal,
            metadata: metadata,
            headers: mergedHeaders,
            body: requestBody,
            trigger: trigger,
            messageId: messageId
        )
    }
}

// Usage
let transport = CustomChatTransport(apiConfig: apiConfig)
let chatInit = try ChatInit(
    transport: transport,
    // ... other params
)
```

## Send Files

```swift
func sendMessageWithFiles(_ text: String, files: [File]) async {
    guard let chat = chat else { return }
    
    currentTask = Task {
        try? await chat.sendMessage(
            input: .text(text, files: files, metadata: nil, messageId: nil)
        )
    }
}
```
