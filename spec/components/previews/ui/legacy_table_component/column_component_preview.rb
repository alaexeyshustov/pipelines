module UI
  class LegacyTableComponent
    class ColumnComponentPreview < ViewComponent::Preview
      def default
        render(UI::LegacyTableComponent::ColumnComponent.new(key: :name, label: "Name"))
      end

      def compact
        render(UI::LegacyTableComponent::ColumnComponent.new(key: :status, label: "Status", style: :compact))
      end

      def with_sort
        render(UI::LegacyTableComponent::ColumnComponent.new(
          key: :name, label: "Name",
          sort_url: "#", sort_active: true, sort_direction: "asc"
        ))
      end
    end
  end
end
