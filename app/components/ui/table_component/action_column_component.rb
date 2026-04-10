# frozen_string_literal: true

module UI
  class TableComponent
    class ActionColumnComponent < ViewComponent::Base
      PADDING_CLASSES = {
        default: "px-4 py-3",
        compact: "px-6 py-3"
      }.freeze

      def initialize(style: :default, actions: nil)
        @style   = style.to_sym
        @actions = actions
      end

      def call
        content_tag(:th, "", class: PADDING_CLASSES.fetch(@style, PADDING_CLASSES[:default]))
      end

      def render_cell(record)
        return "" if @actions.nil?

        padding = ActionCellComponent::PADDING_CLASSES.fetch(@style, ActionCellComponent::PADDING_CLASSES[:default])
        cell_class = "#{padding} text-right flex items-center justify-end gap-3"

        actions_html = @actions.call(record).map { |action|
          ActionCellComponent::ActionSlot.new(**action).render_in(helpers)
        }.join.html_safe

        content_tag(:td, actions_html, class: cell_class)
      end
    end
  end
end
