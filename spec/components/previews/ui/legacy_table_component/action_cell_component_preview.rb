module UI
  class LegacyTableComponent
    class ActionCellComponentPreview < ViewComponent::Preview
      def default
        render(UI::LegacyTableComponent::ActionCellComponent.new) do |cell|
          cell.with_action(label: "Edit",   url: "#", variant: :primary)
          cell.with_action(label: "Delete", url: "#", variant: :danger, method: :delete, confirm: "Delete?")
        end
      end

      def compact
        render(UI::LegacyTableComponent::ActionCellComponent.new(style: :compact)) do |cell|
          cell.with_action(label: "View", url: "#", variant: :neutral)
        end
      end
    end
  end
end
