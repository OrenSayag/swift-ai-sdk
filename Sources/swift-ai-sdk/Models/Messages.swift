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
    public let filename: String
    public let url: URL
    public let mediaType: String
    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "filename": filename,
            "url": url.absoluteString,
            "mediaType": mediaType,
        ]
        return dict
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
