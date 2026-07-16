
module UI
  class TableComponent
    class ActionColumnComponentPreview < ViewComponent::Preview
      def default
        render(UI::TableComponent::ActionColumnComponent.new)
      end

      def compact
        render(UI::TableComponent::ActionColumnComponent.new(style: :compact))
      end
    end
  end
end
