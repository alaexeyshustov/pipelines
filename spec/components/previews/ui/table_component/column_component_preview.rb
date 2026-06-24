# frozen_string_literal: true

module UI
  class TableComponent
    class ColumnComponentPreview < ViewComponent::Preview
      def default
        render(UI::TableComponent::ColumnComponent.new(key: :name, label: "Name"))
      end

      def compact
        render(UI::TableComponent::ColumnComponent.new(key: :status, label: "Status", style: :compact))
      end

      def with_sort
        render(UI::TableComponent::ColumnComponent.new(
          key: :name, label: "Name",
          sort_url: "#", sort_active: true, sort_direction: "asc"
        ))
      end
    end
  end
end
