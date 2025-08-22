import Foundation

public enum UIMessageRole: String {
    case system, user, assistant
}

public protocol MessagePart {
    func asDictionary() -> [String: Any]
}

public enum MessagePartState: String {
    case streaming, done
}

public class TextPart: MessagePart {
    public let type = "text"
    public var text: String
    public var state: MessagePartState?
    public var providerMetadata: Any?

    public init(
        text: String,
        state: MessagePartState? = nil,
        providerMetadata: Any? = nil
    ) {
        self.text = text
        self.state = state
        self.providerMetadata = providerMetadata
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "text": text,
            "type": type,
        ]
        if let state = state {
            dict["state"] = state.rawValue
        }
        if let metadata = providerMetadata {
            dict["providerMetadata"] = metadata
        }
        return dict
    }
}

public class ReasoningPart: MessagePart {
    public let type = "reasoning"
    public var text: String
    public var state: MessagePartState?
    public var providerMetadata: Any?

    public init(
        text: String = "",
        state: MessagePartState? = nil,
        providerMetadata: Any? = nil
    ) {
        self.text = text
        self.state = state
        self.providerMetadata = providerMetadata
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "text": text,
        ]
        if let state = state {
            dict["state"] = state.rawValue
        }
        if let metadata = providerMetadata {
            dict["providerMetadata"] = metadata
        }
        return dict
    }
}

public struct File {
    public let filename: String
    public let url: URL
    public let mediaType: String
}

public struct FilePart: MessagePart {
    public let type = "file"
    public let filename: String?
    public let url: String
    public let mediaType: String
    public let providerMetadata: Any?
    
    public init(
        filename: String? = nil,
        url: String,
        mediaType: String,
        providerMetadata: Any? = nil
    ) {
        self.filename = filename
        self.url = url
        self.mediaType = mediaType
        self.providerMetadata = providerMetadata
    }
    
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "url": url,
            "mediaType": mediaType,
        ]
        if let filename = filename {
            dict["filename"] = filename
        }
        if let metadata = providerMetadata {
            dict["providerMetadata"] = metadata
        }
        return dict
    }
}

public struct SourceUrlPart: MessagePart {
    public let type = "source-url"
    public let sourceId: String
    public let url: String
    public let title: String?
    public let providerMetadata: Any?
    
    public init(
        sourceId: String,
        url: String,
        title: String? = nil,
        providerMetadata: Any? = nil
    ) {
        self.sourceId = sourceId
        self.url = url
        self.title = title
        self.providerMetadata = providerMetadata
    }
    
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "sourceId": sourceId,
            "url": url,
        ]
        if let title = title {
            dict["title"] = title
        }
        if let metadata = providerMetadata {
            dict["providerMetadata"] = metadata
        }
        return dict
    }
}

public struct SourceDocumentPart: MessagePart {
    public let type = "source-document"
    public let sourceId: String
    public let mediaType: String
    public let title: String
    public let filename: String?
    public let providerMetadata: Any?
    
    public init(
        sourceId: String,
        mediaType: String,
        title: String,
        filename: String? = nil,
        providerMetadata: Any? = nil
    ) {
        self.sourceId = sourceId
        self.mediaType = mediaType
        self.title = title
        self.filename = filename
        self.providerMetadata = providerMetadata
    }
    
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "sourceId": sourceId,
            "mediaType": mediaType,
            "title": title,
        ]
        if let filename = filename {
            dict["filename"] = filename
        }
        if let metadata = providerMetadata {
            dict["providerMetadata"] = metadata
        }
        return dict
    }
}

public enum ToolCallState: String {
    case inputStreaming = "input-streaming"
    case inputAvailable = "input-available"
    case outputAvailable = "output-available"
    case outputError = "output-error"
}

public class ToolPart: MessagePart {
    public let toolName: String
    public let toolCallId: String
    public var state: ToolCallState
    public var input: Any?
    public var output: Any?
    public var errorText: String?
    public var providerExecuted: Bool?
    public var callProviderMetadata: Any?
    public var preliminary: Bool?
    
    public var type: String {
        return "tool-\(toolName)"
    }
    
    public init(
        toolName: String,
        toolCallId: String,
        state: ToolCallState,
        input: Any? = nil,
        output: Any? = nil,
        errorText: String? = nil,
        providerExecuted: Bool? = nil,
        callProviderMetadata: Any? = nil,
        preliminary: Bool? = nil
    ) {
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.state = state
        self.input = input
        self.output = output
        self.errorText = errorText
        self.providerExecuted = providerExecuted
        self.callProviderMetadata = callProviderMetadata
        self.preliminary = preliminary
    }
    
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "toolCallId": toolCallId,
            "state": state.rawValue,
        ]
        if let input = input {
            dict["input"] = input
        }
        if let output = output {
            dict["output"] = output
        }
        if let errorText = errorText {
            dict["errorText"] = errorText
        }
        if let providerExecuted = providerExecuted {
            dict["providerExecuted"] = providerExecuted
        }
        if let metadata = callProviderMetadata {
            dict["callProviderMetadata"] = metadata
        }
        if let preliminary = preliminary {
            dict["preliminary"] = preliminary
        }
        return dict
    }
}

public class DynamicToolPart: MessagePart {
    public let type = "dynamic-tool"
    public let toolName: String
    public let toolCallId: String
    public var state: ToolCallState
    public var input: Any?
    public var output: Any?
    public var errorText: String?
    public var callProviderMetadata: Any?
    public var preliminary: Bool?
    
    public init(
        toolName: String,
        toolCallId: String,
        state: ToolCallState,
        input: Any? = nil,
        output: Any? = nil,
        errorText: String? = nil,
        callProviderMetadata: Any? = nil,
        preliminary: Bool? = nil
    ) {
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.state = state
        self.input = input
        self.output = output
        self.errorText = errorText
        self.callProviderMetadata = callProviderMetadata
        self.preliminary = preliminary
    }
    
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "toolName": toolName,
            "toolCallId": toolCallId,
            "state": state.rawValue,
        ]
        if let input = input {
            dict["input"] = input
        }
        if let output = output {
            dict["output"] = output
        }
        if let errorText = errorText {
            dict["errorText"] = errorText
        }
        if let metadata = callProviderMetadata {
            dict["callProviderMetadata"] = metadata
        }
        if let preliminary = preliminary {
            dict["preliminary"] = preliminary
        }
        return dict
    }
}

public class DataPart: MessagePart {
    public let dataName: String
    public let id: String?
    public let data: Any
    
    public var type: String {
        return "data-\(dataName)"
    }
    
    public init(
        dataName: String,
        data: Any,
        id: String? = nil
    ) {
        self.dataName = dataName
        self.data = data
        self.id = id
    }
    
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "data": data,
        ]
        if let id = id {
            dict["id"] = id
        }
        return dict
    }
}

public struct StepStartPart: MessagePart {
    public let type = "step-start"
    
    public init() {}
    
    public func asDictionary() -> [String: Any] {
        return ["type": type]
    }
}

public class UIMessage {
    public let id: String
    public let role: UIMessageRole
    public var parts: [MessagePart]
    public var metadata: [String: Any]?
    public init(
        id: String, role: UIMessageRole, parts: [MessagePart], metadata: [String: Any]? = nil
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.metadata = metadata
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "role": role.rawValue,
            "parts": parts.map { $0.asDictionary() },
        ]
        if let metadata = metadata {
            dict["metadata"] = metadata
        }
        return dict
    }
}

public extension MessagePart {
    func isToolPart() -> Bool {
        return self is ToolPart
    }
    
    func isDynamicToolPart() -> Bool {
        return self is DynamicToolPart
    }
    
    func getToolName() -> String? {
        if let toolPart = self as? ToolPart {
            return toolPart.toolName
        } else if let dynamicToolPart = self as? DynamicToolPart {
            return dynamicToolPart.toolName
        }
        return nil
    }
}
