# frozen_string_literal: true

module Chats
  class MessageComponentPreview < ViewComponent::Preview
    def user_message
      message = Message.new(
        id: 1, role: "user", content: "What emails did I receive today?",
        thinking_text: nil, input_tokens: 0, output_tokens: 0, cached_tokens: 0,
        created_at: Time.current
      )
      allow_message_tool_calls(message, [])
      render(Chats::MessageComponent.new(message: message))
    end

    def assistant_message
      message = Message.new(
        id: 2, role: "assistant", content: "You received 5 emails today.",
        thinking_text: nil, input_tokens: 120, output_tokens: 30, cached_tokens: 0,
        created_at: Time.current
      )
      allow_message_tool_calls(message, [])
      render(Chats::MessageComponent.new(message: message))
    end

    def assistant_with_thinking
      message = Message.new(
        id: 3, role: "assistant",
        content: "Based on my analysis, you received 5 emails.",
        thinking_text: "Let me think about the email patterns...",
        input_tokens: 200, output_tokens: 80, cached_tokens: 50,
        created_at: Time.current
      )
      allow_message_tool_calls(message, [])
      render(Chats::MessageComponent.new(message: message))
    end

    def tool_message
      message = Message.new(
        id: 4, role: "tool", content: nil,
        thinking_text: nil, input_tokens: 0, output_tokens: 0, cached_tokens: 0,
        created_at: Time.current
      )
      allow_message_tool_calls(message, [])
      render(Chats::MessageComponent.new(message: message))
    end

    private

    def allow_message_tool_calls(message, tool_calls)
      message.define_singleton_method(:tool_calls) { tool_calls }
    end
  end
end
