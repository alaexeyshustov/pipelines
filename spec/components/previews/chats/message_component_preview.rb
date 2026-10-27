# frozen_string_literal: true

module Chats
  class MessageComponentPreview < ViewComponent::Preview
    def user_message
      message = Message.new(
        id: 1, role: "user", content: "What emails did I receive today?",
        thinking_text: nil, created_at: Time.current
      )
      stub_message(message)
      render(Chats::MessageComponent.new(message: message))
    end

    def assistant_message
      message = Message.new(
        id: 2, role: "assistant", content: "You received 5 emails today.",
        thinking_text: nil, created_at: Time.current
      )
      stub_message(message, input: 120, output: 30)
      render(Chats::MessageComponent.new(message: message))
    end

    def assistant_with_thinking
      message = Message.new(
        id: 3, role: "assistant",
        content: "Based on my analysis, you received 5 emails.",
        thinking_text: "Let me think about the email patterns...",
        created_at: Time.current
      )
      stub_message(message, input: 200, output: 80, cache_read: 50)
      render(Chats::MessageComponent.new(message: message))
    end

    def tool_message
      message = Message.new(
        id: 4, role: "tool", content: nil,
        thinking_text: nil, created_at: Time.current
      )
      stub_message(message)
      render(Chats::MessageComponent.new(message: message))
    end

    private

    def stub_message(message, input: 0, output: 0, cache_read: 0)
      tokens = RubyLLM::Tokens.new(input: input, output: output, cache_read: cache_read)
      message.define_singleton_method(:tool_calls) { {} }
      message.define_singleton_method(:tokens) { tokens }
    end
  end
end
