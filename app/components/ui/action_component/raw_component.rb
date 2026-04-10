# frozen_string_literal: true

module UI
  class ActionComponent
    class RawComponent < ViewComponent::Base
      def call
        content
      end
    end
  end
end
