import Foundation

// MARK: - UIMessageChunk Types

public enum UIMessageChunk: @unchecked Sendable {
    case textStart(id: String, providerMetadata: ProviderMetadata?)
    case textDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case textEnd(id: String, providerMetadata: ProviderMetadata?)
    case reasoningStart(id: String, providerMetadata: ProviderMetadata?)
    case reasoningDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case reasoningEnd(id: String, providerMetadata: ProviderMetadata?)
    case error(errorText: String)

    case toolInputAvailable(
        toolCallId: String,
        toolName: String,
        input: Any,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        dynamic: Bool?
    )
    case toolInputError(
        toolCallId: String,
        toolName: String,
        input: Any,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        dynamic: Bool?,
        errorText: String
    )
    case toolOutputAvailable(
        toolCallId: String,
        output: Any,
        providerExecuted: Bool?,
        dynamic: Bool?,
        preliminary: Bool?
    )
    case toolOutputError(
        toolCallId: String,
        errorText: String,
        providerExecuted: Bool?,
        dynamic: Bool?
    )
    case toolInputStart(
        toolCallId: String,
        toolName: String,
        providerExecuted: Bool?,
        dynamic: Bool?
    )
    case toolInputDelta(
        toolCallId: String,
        inputTextDelta: String
    )
    case sourceUrl(
        sourceId: String,
        url: String,
        title: String?,
        providerMetadata: ProviderMetadata?
    )
    case sourceDocument(
        sourceId: String,
        mediaType: String,
        title: String,
        filename: String?,
        providerMetadata: ProviderMetadata?
    )
    case file(
        url: String,
        mediaType: String,
        providerMetadata: ProviderMetadata?
    )
    case startStep
    case finishStep
    case start(
        messageId: String?,
        messageMetadata: Any?
    )
    case finish(
        messageMetadata: Any?
    )
    case abort
    case messageMetadata(
        messageMetadata: Any
    )
    // Data chunk: Use associated struct for type safety if you build out data types
    case dataChunk(type: String, id: String?, data: Any, transient: Bool?)
}

public struct ProviderMetadata: Codable {
    public static func from(_: Any?) -> ProviderMetadata? {
        print("ProviderMetadata not implemented")
        return ProviderMetadata(
        )
    }
}

extension UIMessageChunk {
    public static func from(json: Any) -> UIMessageChunk? {
        guard let dict = json as? [String: Any],
              let type = dict["type"] as? String
        else {
            return nil
        }
        switch type {
        case "text-start": return fromTextStart(dict)
        case "text-delta": return fromTextDelta(dict)
        case "text-end": return fromTextEnd(dict)
        case "reasoning-start": return fromReasoningStart(dict)
        case "reasoning-delta": return fromReasoningDelta(dict)
        case "reasoning-end": return fromReasoningEnd(dict)
        case "error": return fromError(dict)
        case "tool-input-available": return fromToolInputAvailable(dict)
        case "tool-input-error": return fromToolInputError(dict)
        case "tool-output-available": return fromToolOutputAvailable(dict)
        case "tool-output-error": return fromToolOutputError(dict)
        case "tool-input-start": return fromToolInputStart(dict)
        case "tool-input-delta": return fromToolInputDelta(dict)
        case "source-url": return fromSourceUrl(dict)
        case "source-document": return fromSourceDocument(dict)
        case "file": return fromFile(dict)
        case "start-step": return .startStep
        case "finish-step": return .finishStep
        case "start": return fromStart(dict)
        case "finish": return fromFinish(dict)
        case "abort": return .abort
        case "message-metadata": return fromMessageMetadata(dict)
        default:
            if type.starts(with: "data-") {
                return fromDataChunk(type: type, dict: dict)
            }
            return nil
        }
    }

    // MARK: - Helper Constructors

    private static func fromTextStart(_ dict: [String: Any]) -> UIMessageChunk? {
        .textStart(
            id: dict["id"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromTextDelta(_ dict: [String: Any]) -> UIMessageChunk? {
        .textDelta(
            id: dict["id"] as? String ?? "",
            delta: dict["delta"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromTextEnd(_ dict: [String: Any]) -> UIMessageChunk? {
        .textEnd(
            id: dict["id"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromReasoningStart(_ dict: [String: Any]) -> UIMessageChunk? {
        .reasoningStart(
            id: dict["id"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromReasoningDelta(_ dict: [String: Any]) -> UIMessageChunk? {
        .reasoningDelta(
            id: dict["id"] as? String ?? "",
            delta: dict["delta"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromReasoningEnd(_ dict: [String: Any]) -> UIMessageChunk? {
        .reasoningEnd(
            id: dict["id"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromError(_ dict: [String: Any]) -> UIMessageChunk? {
        .error(
            errorText: dict["errorText"] as? String ?? ""
        )
    }

    private static func fromToolInputAvailable(_ dict: [String: Any]) -> UIMessageChunk? {
        .toolInputAvailable(
            toolCallId: dict["toolCallId"] as? String ?? "",
            toolName: dict["toolName"] as? String ?? "",
            input: dict["input"] ?? NSNull(),
            providerExecuted: dict["providerExecuted"] as? Bool,
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"]),
            dynamic: dict["dynamic"] as? Bool
        )
    }

    private static func fromToolInputError(_ dict: [String: Any]) -> UIMessageChunk? {
        .toolInputError(
            toolCallId: dict["toolCallId"] as? String ?? "",
            toolName: dict["toolName"] as? String ?? "",
            input: dict["input"] ?? NSNull(),
            providerExecuted: dict["providerExecuted"] as? Bool,
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"]),
            dynamic: dict["dynamic"] as? Bool,
            errorText: dict["errorText"] as? String ?? ""
        )
    }

    private static func fromToolOutputAvailable(_ dict: [String: Any]) -> UIMessageChunk? {
        .toolOutputAvailable(
            toolCallId: dict["toolCallId"] as? String ?? "",
            output: dict["output"] ?? NSNull(),
            providerExecuted: dict["providerExecuted"] as? Bool,
            dynamic: dict["dynamic"] as? Bool,
            preliminary: dict["preliminary"] as? Bool
        )
    }

    private static func fromToolOutputError(_ dict: [String: Any]) -> UIMessageChunk? {
        .toolOutputError(
            toolCallId: dict["toolCallId"] as? String ?? "",
            errorText: dict["errorText"] as? String ?? "",
            providerExecuted: dict["providerExecuted"] as? Bool,
            dynamic: dict["dynamic"] as? Bool
        )
    }

    private static func fromToolInputStart(_ dict: [String: Any]) -> UIMessageChunk? {
        .toolInputStart(
            toolCallId: dict["toolCallId"] as? String ?? "",
            toolName: dict["toolName"] as? String ?? "",
            providerExecuted: dict["providerExecuted"] as? Bool,
            dynamic: dict["dynamic"] as? Bool
        )
    }

    private static func fromToolInputDelta(_ dict: [String: Any]) -> UIMessageChunk? {
        .toolInputDelta(
            toolCallId: dict["toolCallId"] as? String ?? "",
            inputTextDelta: dict["inputTextDelta"] as? String ?? ""
        )
    }

    private static func fromSourceUrl(_ dict: [String: Any]) -> UIMessageChunk? {
        .sourceUrl(
            sourceId: dict["sourceId"] as? String ?? "",
            url: dict["url"] as? String ?? "",
            title: dict["title"] as? String,
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromSourceDocument(_ dict: [String: Any]) -> UIMessageChunk? {
        .sourceDocument(
            sourceId: dict["sourceId"] as? String ?? "",
            mediaType: dict["mediaType"] as? String ?? "",
            title: dict["title"] as? String ?? "",
            filename: dict["filename"] as? String,
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromFile(_ dict: [String: Any]) -> UIMessageChunk? {
        .file(
            url: dict["url"] as? String ?? "",
            mediaType: dict["mediaType"] as? String ?? "",
            providerMetadata: ProviderMetadata.from(dict["providerMetadata"])
        )
    }

    private static func fromStart(_ dict: [String: Any]) -> UIMessageChunk? {
        .start(
            messageId: dict["messageId"] as? String,
            messageMetadata: dict["messageMetadata"]
        )
    }

    private static func fromFinish(_ dict: [String: Any]) -> UIMessageChunk? {
        .finish(
            messageMetadata: dict["messageMetadata"]
        )
    }

    private static func fromMessageMetadata(_ dict: [String: Any]) -> UIMessageChunk? {
        guard let messageMetadata = dict["messageMetadata"] else { return nil }
        return .messageMetadata(messageMetadata: messageMetadata)
    }

    private static func fromDataChunk(type: String, dict: [String: Any]) -> UIMessageChunk? {
        .dataChunk(
            type: type,
            id: dict["id"] as? String,
            data: dict["data"] ?? NSNull(),
            transient: dict["transient"] as? Bool
        )
    }
}
