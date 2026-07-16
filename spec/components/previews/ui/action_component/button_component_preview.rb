
module UI
  class ActionComponent
    class ButtonComponentPreview < ViewComponent::Preview
      def default
        render(UI::ActionComponent::ButtonComponent.new(label: "Submit", url: "#", method: :post))
      end

      def primary
        render(UI::ActionComponent::ButtonComponent.new(label: "Create", url: "#", method: :post, variant: :primary))
      end

      def danger_with_confirm
        render(UI::ActionComponent::ButtonComponent.new(
          label: "Delete",
          url: "#",
          method: :delete,
          variant: :danger,
          confirm: "Are you sure?"
        ))
      end
    end
  end
end
