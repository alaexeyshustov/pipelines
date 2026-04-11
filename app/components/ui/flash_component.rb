# frozen_string_literal: true

module UI
  class FlashComponent < ViewComponent::Base
    def initialize(flash:)
      @flash = flash
    end

    def render?
      @flash.any?
    end

    private

    def classes_for(type)
      case type.to_s
      when "notice"
        "bg-green-50 text-green-800 border border-green-200"
      when "alert", "error"
        "bg-red-50 text-red-800 border border-red-200"
      else
        "bg-blue-50 text-blue-800 border border-blue-200"
      end
    end
  end
end
