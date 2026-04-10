# frozen_string_literal: true

module UI
  class ActionComponent
    class ButtonComponent < ViewComponent::Base
      def initialize(label:, url:, method: :post, variant: nil, confirm: nil, data: {})
        @label   = label
        @url     = url
        @method  = method || :post
        @variant = variant
        @confirm = confirm
        @data    = data || {}
      end

      def button_classes
        return ActionComponent::BUTTON_CLASSES if @variant.nil?

        "#{ActionComponent::BASE_CLASSES} cursor-pointer #{ActionComponent::VARIANT_CLASSES.fetch(@variant)}"
      end

      def button_data
        return @data if @confirm.nil?

        @data.merge(turbo_confirm: @confirm)
      end
    end
  end
end
