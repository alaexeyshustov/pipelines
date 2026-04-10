# frozen_string_literal: true

module UI
  class TableComponent
    class ColumnComponent < ViewComponent::Base
      HEADER_CLASSES = {
        default: "px-4 py-3 text-left font-medium text-gray-600",
        compact: "px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider"
      }.freeze

      PADDING_CLASSES = {
        default: "px-4 py-3",
        compact: "px-6 py-4"
      }.freeze

      def initialize(key = nil, label: nil, style: :default, classes: nil, variant: nil, cell: nil, badge_component: nil, component: nil, props: nil, sort_url: nil, sort_active: false, sort_direction: nil)
        @key             = key
        @label           = label || derive_label(key)
        @style           = style.to_sym
        @classes         = classes
        @variant         = variant&.to_sym
        @cell            = cell
        @badge_component = badge_component
        @component       = component
        @props           = props
        @sort_url        = sort_url
        @sort_active     = sort_active
        @sort_direction  = sort_direction
      end

      def call
        if @sort_url
          content_tag(:th, class: resolved_classes) do
            link_to(@sort_url, class: sort_link_classes) do
              safe_join([ @label.to_s, sort_indicator ].compact)
            end
          end
        else
          content_tag(:th, content.presence || @label.to_s, class: resolved_classes)
        end
      end

      def render_cell(record)
        content_tag(:td, cell_value(record), class: cell_css_classes)
      end

      private

      def cell_value(record)
        if @badge_component
          @badge_component.new(status: record.public_send(@key)).render_in(helpers)
        elsif @component
          resolved_props = @props ? @props.call(record) : {}
          @component.new(**resolved_props).render_in(helpers)
        elsif @cell
          @cell.call(record)
        elsif @key
          record.public_send(@key).to_s
        else
          ""
        end
      end

      def cell_css_classes
        return @classes if @classes

        parts = [ CellComponent::PADDING_CLASSES.fetch(@style, CellComponent::PADDING_CLASSES[:default]) ]
        parts << CellComponent::VARIANT_CLASSES[@variant] if @variant && CellComponent::VARIANT_CLASSES.key?(@variant)
        parts.join(" ")
      end

      def resolved_classes
        return "px-4 py-3" if @label.nil? && !content.present?

        HEADER_CLASSES.fetch(@style, HEADER_CLASSES[:default])
      end

      def derive_label(key)
        return nil if key.nil?

        key.to_s.titleize
      end

      def sort_link_classes
        base = "inline-flex items-center gap-1 hover:text-gray-900"
        @sort_active ? "#{base} text-gray-900" : base
      end

      def sort_indicator
        return unless @sort_active

        content_tag(:span, @sort_direction == "asc" ? "↑" : "↓", class: "text-gray-400")
      end
    end
  end
end
