import Foundation

public extension Chat {
    func makeRequest(input: MakeRequestInput) async throws {
        setStatus(status: .submitted, error: nil)

        let streamingState = createStreamingUIMessageState(
            lastMessage: lastMessage,
            messageId: generateId()
        )

        // TODO: implement task fpr aborting/canceling the request
        activeResponse = ActiveResponse(state: streamingState, task: nil)

        var stream: AsyncStream<UIMessageChunk>

        do {
            defer {
                activeResponse = nil
            }
            if input.trigger == .resumeStream {
                guard
                    let reconnectStream = try await transport.reconnectToStream(
                        chatId: id,
                        metadata: input.options?.metadata,
                        headers: input.options?.headers,
                        body: input.options?.body,
                        path: nil
                    )
                else {
                    setStatus(status: .ready)
                    // No active stream to resume
                    return
                }
                stream = reconnectStream
            } else {
                stream = try await transport.sendMessages(
                    chatId: id,
                    messages: messages,
                    abortSignal: nil,
                    metadata: input.options?.metadata,
                    headers: input.options?.headers,
                    body: input.options?.body,
                    trigger: input.trigger,
                    messageId: input.messageId
                )
            }

            var thrownError: Error?
            let asyncStream = processUIMessageStream(
                options: ProcessUIMessageStreamOptions(
                    stream: stream,
                    runUpdateMessageJob: { chunk in
                        self.setStatus(status: .streaming)

                        guard var activeResponse = self.activeResponse else { return }

                        switch chunk {
                        case let .textStart(id, providerMetadata):
                            let textPart = TextPart(
                                text: "", state: .streaming, providerMetadata: providerMetadata
                            )
                            activeResponse.state.activeTextParts[id] = textPart
                            activeResponse.state.message.parts.append(textPart)
                        case let .textDelta(id, delta, providerMetadata):
                            if let textPart = activeResponse.state.activeTextParts[id] as? TextPart {
                                textPart.text += delta
                                if let providerMetadata = providerMetadata {
                                    textPart.providerMetadata = providerMetadata
                                }
                                activeResponse.state.activeTextParts[id] = textPart
                            }
                        case let .textEnd(id, providerMetadata):
                            if let textPart = activeResponse.state.activeTextParts[id] as? TextPart {
                                if let providerMetadata = providerMetadata {
                                    textPart.providerMetadata = providerMetadata
                                }
                                textPart.state = .done
                                activeResponse.state.activeTextParts.removeValue(forKey: id)
                            }
                        case let .reasoningStart(id, providerMetadata):
                            let reasoningPart = ReasoningPart(
                                text: "",
                                state: .streaming,
                                providerMetadata: providerMetadata
                            )
                            activeResponse.state.activeReasoningParts[id] = reasoningPart
                            activeResponse.state.message.parts.append(reasoningPart)
                        case let .reasoningDelta(id, delta, providerMetadata):
                            if let reasoningPart = activeResponse.state.activeReasoningParts[id] as? ReasoningPart {
                                reasoningPart.text += delta
                                if let providerMetadata = providerMetadata {
                                    reasoningPart.providerMetadata = providerMetadata
                                }
                                activeResponse.state.activeReasoningParts[id] = reasoningPart
                            }
                        case let .reasoningEnd(id, providerMetadata):
                            if let reasoningPart = activeResponse.state.activeReasoningParts[id] as? ReasoningPart {
                                if let providerMetadata = providerMetadata {
                                    reasoningPart.providerMetadata = providerMetadata
                                }
                                reasoningPart.state = .done
                                activeResponse.state.activeReasoningParts.removeValue(forKey: id)
                            }
                        case let .file(url, mediaType, providerMetadata):
                            let filePart = FilePart(
                                url: url,
                                mediaType: mediaType,
                                providerMetadata: providerMetadata
                            )
                            activeResponse.state.message.parts.append(filePart)
                        case let .sourceUrl(sourceId, url, title, providerMetadata):
                            let sourceUrlPart = SourceUrlPart(
                                sourceId: sourceId,
                                url: url,
                                title: title,
                                providerMetadata: providerMetadata
                            )
                            activeResponse.state.message.parts.append(sourceUrlPart)
                        case let .sourceDocument(sourceId, mediaType, title, filename, providerMetadata):
                            let sourceDocumentPart = SourceDocumentPart(
                                sourceId: sourceId,
                                mediaType: mediaType,
                                title: title,
                                filename: filename,
                                providerMetadata: providerMetadata
                            )
                            activeResponse.state.message.parts.append(sourceDocumentPart)
                        case let .toolInputStart(toolCallId, toolName, providerExecuted, dynamic):
                            if dynamic == true {
                                let dynamicToolPart = DynamicToolPart(
                                    toolName: toolName,
                                    toolCallId: toolCallId,
                                    state: .inputStreaming
                                )
                                activeResponse.state.message.parts.append(dynamicToolPart)
                            } else {
                                let toolPart = ToolPart(
                                    toolName: toolName,
                                    toolCallId: toolCallId,
                                    state: .inputStreaming,
                                    providerExecuted: providerExecuted
                                )
                                activeResponse.state.message.parts.append(toolPart)
                            }
                        case let .toolInputDelta(toolCallId, inputTextDelta):
                            // Find the tool part and update it with partial input
                            if let toolPart = activeResponse.state.message.parts.first(where: {
                                ($0 as? ToolPart)?.toolCallId == toolCallId
                            }) as? ToolPart {
                                // NOTE: consider parsing the partial JSON as typescript version does, will be useful for UX if rendered
                                // For now, just store the delta as text
                                toolPart.input = (toolPart.input as? String ?? "") + inputTextDelta
                            } else if let dynamicToolPart = activeResponse.state.message.parts.first(where: {
                                ($0 as? DynamicToolPart)?.toolCallId == toolCallId
                            }) as? DynamicToolPart {
                                dynamicToolPart.input = (dynamicToolPart.input as? String ?? "") + inputTextDelta
                            }
                        case let .toolInputAvailable(toolCallId, toolName, input, providerExecuted, providerMetadata, dynamic):
                            if dynamic == true {
                                if let dynamicToolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? DynamicToolPart)?.toolCallId == toolCallId
                                }) as? DynamicToolPart {
                                    dynamicToolPart.state = .inputAvailable
                                    dynamicToolPart.input = input
                                    dynamicToolPart.callProviderMetadata = providerMetadata
                                } else {
                                    let dynamicToolPart = DynamicToolPart(
                                        toolName: toolName,
                                        toolCallId: toolCallId,
                                        state: .inputAvailable,
                                        input: input,
                                        callProviderMetadata: providerMetadata
                                    )
                                    activeResponse.state.message.parts.append(dynamicToolPart)
                                }
                            } else {
                                if let toolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? ToolPart)?.toolCallId == toolCallId
                                }) as? ToolPart {
                                    toolPart.state = .inputAvailable
                                    toolPart.input = input
                                    toolPart.providerExecuted = providerExecuted
                                    toolPart.callProviderMetadata = providerMetadata
                                } else {
                                    let toolPart = ToolPart(
                                        toolName: toolName,
                                        toolCallId: toolCallId,
                                        state: .inputAvailable,
                                        input: input,
                                        providerExecuted: providerExecuted,
                                        callProviderMetadata: providerMetadata
                                    )
                                    activeResponse.state.message.parts.append(toolPart)
                                }
                            }
                            // Only call onToolCall for non-provider-executed tools
                            if providerExecuted != true {
                                self.onToolCall?(chunk)
                            }
                        case let .toolInputError(toolCallId, toolName, input, providerExecuted, providerMetadata, dynamic, errorText):
                            if dynamic == true {
                                if let dynamicToolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? DynamicToolPart)?.toolCallId == toolCallId
                                }) as? DynamicToolPart {
                                    dynamicToolPart.state = .outputError
                                    dynamicToolPart.input = input
                                    dynamicToolPart.errorText = errorText
                                    dynamicToolPart.callProviderMetadata = providerMetadata
                                } else {
                                    let dynamicToolPart = DynamicToolPart(
                                        toolName: toolName,
                                        toolCallId: toolCallId,
                                        state: .outputError,
                                        input: input,
                                        errorText: errorText,
                                        callProviderMetadata: providerMetadata
                                    )
                                    activeResponse.state.message.parts.append(dynamicToolPart)
                                }
                            } else {
                                if let toolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? ToolPart)?.toolCallId == toolCallId
                                }) as? ToolPart {
                                    toolPart.state = .outputError
                                    toolPart.input = input
                                    toolPart.errorText = errorText
                                    toolPart.providerExecuted = providerExecuted
                                    toolPart.callProviderMetadata = providerMetadata
                                } else {
                                    let toolPart = ToolPart(
                                        toolName: toolName,
                                        toolCallId: toolCallId,
                                        state: .outputError,
                                        input: input,
                                        errorText: errorText,
                                        providerExecuted: providerExecuted,
                                        callProviderMetadata: providerMetadata
                                    )
                                    activeResponse.state.message.parts.append(toolPart)
                                }
                            }
                        case let .toolOutputAvailable(toolCallId, output, providerExecuted, dynamic, preliminary):
                            if dynamic == true {
                                if let dynamicToolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? DynamicToolPart)?.toolCallId == toolCallId
                                }) as? DynamicToolPart {
                                    dynamicToolPart.state = .outputAvailable
                                    dynamicToolPart.output = output
                                    dynamicToolPart.preliminary = preliminary
                                }
                            } else {
                                if let toolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? ToolPart)?.toolCallId == toolCallId
                                }) as? ToolPart {
                                    toolPart.state = .outputAvailable
                                    toolPart.output = output
                                    toolPart.providerExecuted = providerExecuted
                                    toolPart.preliminary = preliminary
                                }
                            }
                        case let .toolOutputError(toolCallId, errorText, providerExecuted, dynamic):
                            if dynamic == true {
                                if let dynamicToolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? DynamicToolPart)?.toolCallId == toolCallId
                                }) as? DynamicToolPart {
                                    dynamicToolPart.state = .outputError
                                    dynamicToolPart.errorText = errorText
                                }
                            } else {
                                if let toolPart = activeResponse.state.message.parts.first(where: {
                                    ($0 as? ToolPart)?.toolCallId == toolCallId
                                }) as? ToolPart {
                                    toolPart.state = .outputError
                                    toolPart.errorText = errorText
                                    toolPart.providerExecuted = providerExecuted
                                }
                            }
                        case .startStep:
                            let stepStartPart = StepStartPart()
                            activeResponse.state.message.parts.append(stepStartPart)
                        case .finishStep:
                            // Reset active parts for new step
                            activeResponse.state.activeTextParts = [:]
                            activeResponse.state.activeReasoningParts = [:]
                        case let .start(messageId, messageMetadata):
                            if let messageId = messageId {
                                activeResponse.state.message.id = messageId
                            }
                            if let messageMetadata = messageMetadata {
                                activeResponse.state.message.metadata = messageMetadata as? [String: Any]
                            }
                        case let .finish(messageMetadata):
                            if let messageMetadata = messageMetadata {
                                activeResponse.state.message.metadata = messageMetadata as? [String: Any]
                            }
                        case let .messageMetadata(messageMetadata):
                            activeResponse.state.message.metadata = messageMetadata as? [String: Any]
                        case let .dataChunk(type, id, data, transient):
                            let dataPart = DataPart(
                                dataName: String(type.dropFirst(5)), // Remove "data-" prefix
                                data: data,
                                id: id
                            )
                            // Only add non-transient data parts to the message
                            if transient != true {
                                activeResponse.state.message.parts.append(dataPart)
                            }
                            self.onData?(chunk)
                        case let .error(errorText):
                            self.onError?(
                                NSError(
                                    domain: "Chat", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: errorText]
                                ))
                        case .abort:
                            // Handle abort if needed
                            break
                        case .reasoning, .reasoningPartFinish:
                            // These might be legacy cases, handle if needed
                            break
                        }

                        self.activeResponse = activeResponse

                        let replaceLastMessage =
                            activeResponse.state.message.id == self.lastMessage?.id

                        if replaceLastMessage {
                            self.state.replaceMessage(
                                at: self.state.messages.count - 1,
                                with: activeResponse.state.message
                            )
                        } else {
                            self.state.pushMessage(activeResponse.state.message)
                        }
                    },
                    onError: { error in
                        thrownError = error
                        self.onError?(error)
                    },
                    onToolCall: { toolCall in
                        self.onToolCall?(toolCall)
                    },
                    onData: { data in
                        self.onData?(data)
                    }
                )
            )

            for await _ in asyncStream {
                // The stream processing is handled in processUIMessageStream
            }

            if let thrownError {
                throw thrownError
            }

            guard let lastSessionMessage = activeResponse?.state.message ?? lastMessage else {
                throw ChatError.invalidLastSessionMessage(id: input.messageId ?? "unknown")
            }
            onFinish?(lastSessionMessage)
            setStatus(status: .ready)

        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSUserCancelledError
            {
                setStatus(status: .ready)
            } else {
                onError?(error)
                setStatus(status: .error, error: error)
            }
            throw error
        }
        if let sendAuto = sendAutomaticallyWhen, sendAuto(state.messages) {
            guard autoSendRecursionCount < maxToolCalls else {
                throw ChatError.tooManyRecursionAttempts(id: input.messageId ?? "unknown")
            }
            autoSendRecursionCount += 1
            defer { autoSendRecursionCount -= 1 }
            try await makeRequest(
                input: MakeRequestInput(
                    trigger: .submitMessage,
                    messageId: lastMessage?.id,
                    options: input.options
                ))
        }
    }
}
