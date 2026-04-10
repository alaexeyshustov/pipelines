# frozen_string_literal: true

module UI
  class ActionComponent
    class LinkComponent < ViewComponent::Base
      def initialize(label:, url:, variant: nil)
        @label   = label
        @url     = url
        @variant = variant
      end

      def link_classes
        return ActionComponent::LINK_CLASSES if @variant.nil?
        return "text-sm text-gray-500 hover:text-gray-700" if @variant == :ghost

        "#{ActionComponent::BASE_CLASSES} #{ActionComponent::VARIANT_CLASSES.fetch(@variant)}"
      end
    end
  end
end
