# Swift AI SDK

A Swift package for consuming AI chat streams from a Vercel AI SDK v5 backend. This SDK provides a clean, reactive interface for building AI-powered chat applications in iOS and macOS.

## Features

- 🚀 **Streaming Chat**: Real-time streaming responses from AI models
- 📱 **iOS & macOS Support**: Works on iOS 15+ and macOS 12+
- 🔄 **Reactive State Management**: Built with Combine for reactive UI updates
- 🛠️ **Customizable Transport**: Easy to extend with custom API configurations
- 📁 **File Support**: Send files and multimedia content
- 🎯 **Tool Calls**: Support for AI tool calling functionality
- ⚡ **Async/Await**: Modern Swift concurrency support

## Installation

Add this package to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/swift-ai-sdk.git", from: "1.0.0")
]
```

## Quick Start

### Basic Setup

```swift
import Combine
import swift_ai_sdk
import SwiftUI

class ChatManager: ObservableObject {
    @Published var messages: [UIMessage] = []
    @Published var status: ChatStatus = .ready
    @Published var error: Error?
    
    private var chat: Chat?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupChat()
    }
    
    private func setupChat() {
        do {
            let apiConfig = ChatTransportApiConfig(
                apiBaseUrl: "https://your-api.com",
                apiChatPath: "/chat"
            )
            
            let chatInit = try ChatInit(
                onError: { [weak self] error in
                    DispatchQueue.main.async {
                        self?.error = error
                    }
                },
                onFinish: { [weak self] message in
                    DispatchQueue.main.async {
                        self?.messages.append(message)
                    }
                },
                defaultChatTransportApiConfig: apiConfig
            )
            
            chat = Chat(chatInit)
            observeState()
            
        } catch {
            print("Failed to setup chat: \(error)")
        }
    }
    
    private func observeState() {
        guard let chat = chat else { return }
        
        // Observe messages
        chat.state.$messages
            .receive(on: DispatchQueue.main)
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)
        
        // Observe status
        chat.state.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.status, on: self)
            .store(in: &cancellables)
        
        // Observe errors
        chat.state.$error
            .receive(on: DispatchQueue.main)
            .assign(to: \.error, on: self)
            .store(in: &cancellables)
    }
    
    func sendMessage(_ text: String) async {
        guard let chat = chat else { return }
        
        do {
            try await chat.sendMessage(
                input: .text(text, files: nil, metadata: nil, messageId: nil)
            )
        } catch {
            print("Failed to send message: \(error)")
        }
    }
}
```

### SwiftUI Integration

```swift
struct ChatView: View {
    @StateObject private var chatManager = ChatManager()
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chatManager.messages, id: \.id) { message in
                        MessageBubble(message: message)
                    }
                }
            }
            
            HStack {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    Task {
                        await chatManager.sendMessage(messageText)
                        messageText = ""
                    }
                }
                .disabled(chatManager.status == .streaming)
            }
            .padding()
        }
    }
}

struct MessageBubble: View {
    let message: UIMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: .leading) {
                ForEach(message.parts, id: \.self) { part in
                    if let textPart = part as? TextPart {
                        Text(textPart.text)
                            .padding()
                            .background(message.role == .user ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}
```

## Advanced Usage

### Custom Transport with Authentication

```swift
class AuthenticatedChatTransport: DefaultChatTransport {
    private let authToken: String
    
    init(apiConfig: ChatTransportApiConfig, authToken: String) {
        self.authToken = authToken
        super.init(apiConfig: apiConfig)
    }
    
    override func sendMessages(
        chatId: String,
        messages: [UIMessage],
        abortSignal: Task<Void, Never>? = nil,
        metadata: [String: Any]? = nil,
        headers: [String: String]? = nil,
        body: [String: Any]? = nil,
        trigger: ChatRequestTrigger,
        messageId: String? = nil
    ) async throws -> AsyncStream<UIMessageChunk> {
        var customHeaders = headers ?? [:]
        customHeaders["Authorization"] = "Bearer \(authToken)"
        
        return try await super.sendMessages(
            chatId: chatId,
            messages: messages,
            abortSignal: abortSignal,
            metadata: metadata,
            headers: customHeaders,
            body: body,
            trigger: trigger,
            messageId: messageId
        )
    }
}

// Usage
let transport = AuthenticatedChatTransport(
    apiConfig: apiConfig,
    authToken: "your-auth-token"
)

let chatInit = try ChatInit(
    transport: transport,
    // ... other parameters
)
```

### Sending Files

```swift
func sendMessageWithFiles(_ text: String, fileURLs: [URL]) async {
    guard let chat = chat else { return }
    
    let files = fileURLs.map { url in
        File(
            filename: url.lastPathComponent,
            url: url,
            mediaType: "application/octet-stream"
        )
    }
    
    do {
        try await chat.sendMessage(
            input: .text(text, files: files, metadata: nil, messageId: nil)
        )
    } catch {
        print("Failed to send message with files: \(error)")
    }
}
```

### Tool Calls Support

```swift
let chatInit = try ChatInit(
    onToolCall: { toolCall in
        print("Tool called: \(toolCall)")
        // Handle tool calls here
    },
    sendAutomaticallyWhen: { messages in
        // Custom logic for when to send messages automatically
        return messages.last?.role == .user
    },
    maxToolCalls: 10,
    // ... other parameters
)
```

### Error Handling

```swift
class ChatManager: ObservableObject {
    @Published var error: Error?
    
    private func setupChat() {
        do {
            let chatInit = try ChatInit(
                onError: { [weak self] error in
                    DispatchQueue.main.async {
                        self?.error = error
                        // Handle specific error types
                        if let chatError = error as? ChatError {
                            switch chatError {
                            case .messageNotFound(let id):
                                print("Message not found: \(id)")
                            case .notUserMessage(let id):
                                print("Not a user message: \(id)")
                            case .tooManyRecursionAttempts(let id):
                                print("Too many recursion attempts: \(id)")
                            case .invalidTransportConfiguration(let id):
                                print("Invalid transport configuration: \(id)")
                            }
                        }
                    }
                },
                // ... other parameters
            )
            
            chat = Chat(chatInit)
        } catch {
            print("Failed to setup chat: \(error)")
        }
    }
}
```

## API Reference

### Chat

The main class for managing chat sessions.

#### Properties
- `id: String` - Unique identifier for the chat
- `state: ChatState` - Current state of the chat
- `status: ChatStatus` - Current status (ready, submitted, streaming, error)
- `error: Error?` - Current error if any
- `messages: [UIMessage]` - Array of messages in the conversation

#### Methods
- `sendMessage(input: SendMessageInput, options: ChatRequestOptions?) async throws` - Send a message
- `setStatus(status: ChatStatus, error: Error?)` - Update chat status
- `clearError()` - Clear current error

### ChatState

Reactive state management for chat data.

#### Published Properties
- `@Published var status: ChatStatus` - Current chat status
- `@Published var error: Error?` - Current error
- `@Published var messages: [UIMessage]` - Messages array

#### Methods
- `pushMessage(_ message: UIMessage)` - Add a message
- `popMessage()` - Remove last message
- `replaceMessage(at index: Int, with message: UIMessage)` - Replace message at index

### SendMessageInput

Input types for sending messages:

```swift
enum SendMessageInput {
    case message(UIMessage, messageId: String?)
    case text(String, files: [File]?, metadata: [String: Any]?, messageId: String?)
    case files([File], metadata: [String: Any]?, messageId: String?)
    case none
}
```

## Requirements

- iOS 15.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Related

- [Vercel AI SDK](https://ai-sdk.dev/) - The backend SDK this package is designed to work with
