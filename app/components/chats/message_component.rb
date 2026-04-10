# frozen_string_literal: true

module Chats
  class MessageComponent < ViewComponent::Base
    with_collection_parameter :message

    ROLE_CONTAINER_CLASSES = {
      "user"      => "bg-blue-50 border-blue-200",
      "assistant" => "bg-white border-gray-200",
      "tool"      => "bg-amber-50 border-amber-200"
    }.freeze

    ROLE_BADGE_CLASSES = {
      "user"      => "bg-blue-100 text-blue-700",
      "assistant" => "bg-gray-100 text-gray-700",
      "tool"      => "bg-amber-100 text-amber-700"
    }.freeze

    DEFAULT_CONTAINER_CLASSES = "bg-gray-50 border-gray-200"
    DEFAULT_BADGE_CLASSES     = "bg-gray-100 text-gray-600"

    def initialize(message:)
      @message = message
    end

    def role_container_classes
      ROLE_CONTAINER_CLASSES.fetch(@message.role, DEFAULT_CONTAINER_CLASSES)
    end

    def role_badge_classes
      ROLE_BADGE_CLASSES.fetch(@message.role, DEFAULT_BADGE_CLASSES)
    end

    def formatted_time
      @message.created_at.strftime("%H:%M:%S")
    end

    def show_input_tokens?
      @message.input_tokens.to_i > 0
    end

    def show_output_tokens?
      @message.output_tokens.to_i > 0
    end

    def show_cached_tokens?
      @message.cached_tokens.to_i > 0
    end
  end
end
