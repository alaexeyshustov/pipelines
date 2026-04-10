# frozen_string_literal: true

module Chats
  class DetailCardComponent < ViewComponent::Base
    def initialize(chat:)
      @chat = chat
    end

    def model_name_value
      @chat.model&.name || "—"
    end

    def message_count
      @chat.messages.size
    end

    def formatted_created_at
      @chat.created_at.strftime("%b %-d, %Y %H:%M:%S")
    end

    def formatted_updated_at
      @chat.updated_at.strftime("%b %-d, %Y %H:%M:%S")
    end
  end
end
