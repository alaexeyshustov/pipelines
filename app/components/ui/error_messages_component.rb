# frozen_string_literal: true

module UI
  class ErrorMessagesComponent < ViewComponent::Base
    def initialize(errors:)
      @errors = errors
    end

    def render?
      @errors.any?
    end
  end
end
