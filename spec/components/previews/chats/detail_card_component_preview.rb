# frozen_string_literal: true

module Chats
  class DetailCardComponentPreview < ViewComponent::Preview
    def default
      chat = Chat.first || Chat.new(id: 1, created_at: Time.current, updated_at: Time.current)
      render(Chats::DetailCardComponent.new(chat: chat))
    end

    def without_model
      chat = Chat.new(id: 2, model: nil, created_at: Time.current, updated_at: Time.current)
      render(Chats::DetailCardComponent.new(chat: chat))
    end
  end
end
