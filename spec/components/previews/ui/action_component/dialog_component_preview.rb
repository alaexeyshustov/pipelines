
module UI
  class ActionComponent
    class DialogComponentPreview < ViewComponent::Preview
      def default
        render(UI::ActionComponent::DialogComponent.new(
          label: "Archive",
          dialog_title: "Archive this record?",
          url: "#",
          method: :post,
          confirm_label: "Archive",
          variant: :neutral
        ))
      end

      def danger
        render(UI::ActionComponent::DialogComponent.new(
          label: "Delete",
          dialog_title: "Delete permanently?",
          url: "#",
          method: :delete,
          confirm_label: "Yes, delete",
          variant: :danger
        ))
      end

      def primary
        render(UI::ActionComponent::DialogComponent.new(
          label: "Approve",
          dialog_title: "Approve this item?",
          url: "#",
          method: :post,
          confirm_label: "Approve",
          variant: :primary
        ))
      end
    end
  end
end
