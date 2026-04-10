# frozen_string_literal: true

module UI
  class TableComponent
    class CellComponent < ViewComponent::Base
      PADDING_CLASSES = {
        default: "px-4 py-3",
        compact: "px-6 py-4"
      }.freeze

      VARIANT_CLASSES = {
        muted:  "text-gray-500",
        subtle: "text-gray-600",
        strong: "font-medium text-gray-900",
        mono:   "font-mono text-xs"
      }.freeze

      def initialize(style: :default, variant: nil, classes: nil)
        @style   = style.to_sym
        @variant = variant&.to_sym
        @classes = classes
      end

      def call
        content_tag(:td, content, class: resolved_classes)
      end

      private

      def resolved_classes
        return @classes if @classes

        parts = [ PADDING_CLASSES.fetch(@style, PADDING_CLASSES[:default]) ]
        parts << VARIANT_CLASSES[@variant] if @variant && VARIANT_CLASSES.key?(@variant)
        parts.join(" ")
      end
    end
  end
end
