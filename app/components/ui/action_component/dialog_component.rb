# frozen_string_literal: true

module UI
  class ActionComponent
    class DialogComponent < ViewComponent::Base
      def initialize(label:, dialog_title:, url:, method: :delete,
                     confirm_label: "Confirm", variant: nil, size: :sm,
                     body_component: nil, body_options: {})
        @label          = label
        @dialog_title   = dialog_title
        @url            = url
        @method         = method
        @confirm_label  = confirm_label
        @variant        = variant || :neutral
        @size           = size.to_sym
        @body_component = body_component
        @body_options   = body_options || {}
        @body_proc      = nil
      end

      def with_body(&block)
        @body_proc = block
        self
      end

      def body?
        @body_component.present? || @body_proc.present?
      end

      def render_body(form_builder = nil)
        if @body_component
          @body_component.new(form: form_builder, **@body_options).render_in(view_context)
        elsif form_builder
          @body_proc.call(form_builder)
        else
          @body_proc.call
        end
      end

      def trigger_classes
        "#{ActionComponent::BASE_CLASSES} cursor-pointer #{ActionComponent::VARIANT_CLASSES.fetch(@variant)}"
      end

      def cancel_classes
        "px-4 py-2 text-sm text-gray-600 border border-gray-200 rounded-lg hover:bg-gray-50 cursor-pointer"
      end

      def confirm_classes
        resolved = ActionComponent::CONFIRM_VARIANT_CLASSES.fetch(@variant, ActionComponent::CONFIRM_VARIANT_CLASSES[:neutral])
        "px-4 py-2 text-sm font-medium rounded-lg cursor-pointer #{resolved}"
      end

      def dialog_css
        max_width = @size == :md ? "max-w-md" : "max-w-sm"
        "rounded-xl shadow-lg border border-gray-200 p-6 w-full #{max_width} " \
          "fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 backdrop:bg-black/30"
      end
    end
  end
end
