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
                        case let .textStart(id, _):
                            activeResponse.state.activeTextParts[id] = TextPart(
                                text: "", state: .streaming
                            )
                            activeResponse.state.message.parts.append(
                                activeResponse.state.activeTextParts[id]!)
                        case let .textDelta(id, delta, _):
                            if var textPart = activeResponse.state.activeTextParts[id] as? TextPart,
                               let existingText = textPart.text as? String
                            {
                                textPart.text = existingText + delta
                                activeResponse.state.activeTextParts[id] = textPart
                            }
                        case let .textEnd(id, _):
                            if var textPart = activeResponse.state.activeTextParts[id] as? TextPart {
                                textPart.state = .done
                                activeResponse.state.activeTextParts[id] = textPart
                            }
                            activeResponse.state.activeTextParts.removeValue(forKey: id)
                        case .reasoningStart, .reasoningDelta, .reasoningEnd:
                            // Extend with similar logic for reasoning parts
                            break
                        case .toolInputAvailable, .toolInputError:
                            self.onToolCall?(chunk)
                        case .dataChunk:
                            self.onData?(chunk)
                        case let .error(errorText):
                            self.onError?(
                                NSError(
                                    domain: "Chat", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: errorText]
                                ))
                        default:
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
