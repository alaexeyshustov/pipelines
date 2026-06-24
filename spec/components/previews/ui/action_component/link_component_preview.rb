# frozen_string_literal: true

module UI
  class ActionComponent
    class LinkComponentPreview < ViewComponent::Preview
      def default
        render(UI::ActionComponent::LinkComponent.new(label: "View Details", url: "#"))
      end

      def primary
        render(UI::ActionComponent::LinkComponent.new(label: "Open", url: "#", variant: :primary))
      end

      def ghost
        render(UI::ActionComponent::LinkComponent.new(label: "Cancel", url: "#", variant: :ghost))
      end
    end
  end
end
