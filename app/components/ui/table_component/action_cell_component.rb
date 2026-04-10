# frozen_string_literal: true

module UI
  class TableComponent
    class ActionCellComponent < ViewComponent::Base
      PADDING_CLASSES = {
        default: "px-4 py-3",
        compact: "px-6 py-4"
      }.freeze

      renders_many :actions, "UI::TableComponent::ActionCellComponent::ActionSlot"

      def initialize(style: :default)
        @style = style.to_sym
      end

      def resolved_classes
        padding = PADDING_CLASSES.fetch(@style, PADDING_CLASSES[:default])
        "#{padding} text-right flex items-center justify-end gap-3"
      end

      class ActionSlot < ViewComponent::Base
        VARIANT_CLASSES = {
          primary: "text-indigo-600 hover:text-indigo-800 font-medium",
          danger:  "text-red-500 hover:text-red-700 font-medium",
          neutral: "text-gray-500 hover:text-gray-700 font-medium"
        }.freeze

        def initialize(label:, url:, variant: :neutral, method: :get, confirm: nil)
          @label   = label
          @url     = url
          @variant = variant.to_sym
          @method  = method
          @confirm = confirm
        end

        def call
          if non_get?
            form_options = @confirm ? { data: { turbo_confirm: @confirm } } : {}
            button_to(@label, @url, method: @method, form: form_options, class: button_classes)
          else
            link_to(@label, @url, class: link_classes)
          end
        end

        private

        def link_classes
          VARIANT_CLASSES.fetch(@variant, VARIANT_CLASSES[:neutral])
        end

        def button_classes
          "#{link_classes} bg-transparent border-0 cursor-pointer p-0"
        end

        def non_get?
          ![ :get, "get" ].include?(@method)
        end
      end
    end
  end
end
