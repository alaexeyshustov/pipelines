# frozen_string_literal: true

module UI
  class ActionComponent
    class DeleteComponentPreview < ViewComponent::Preview
      def default
        render(UI::ActionComponent::DeleteComponent.new(label: "Delete", url: "#"))
      end

      def with_confirm
        render(UI::ActionComponent::DeleteComponent.new(
          label: "Delete Record",
          url: "#",
          confirm: "This action cannot be undone. Continue?"
        ))
      end
    end
  end
end
