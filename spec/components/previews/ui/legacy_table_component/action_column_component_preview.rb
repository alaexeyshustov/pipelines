module UI
  class LegacyTableComponent
    class ActionColumnComponentPreview < ViewComponent::Preview
      def default
        render(UI::LegacyTableComponent::ActionColumnComponent.new)
      end

      def compact
        render(UI::LegacyTableComponent::ActionColumnComponent.new(style: :compact))
      end
    end
  end
end
