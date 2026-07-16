
module UI
  class ActionComponentPreview < ViewComponent::Preview
    def link
      render(UI::ActionComponent.new(type: :link, label: "View", url: "#", variant: :primary))
    end

    def button
      render(UI::ActionComponent.new(type: :button, label: "Run", url: "#", method: :post, variant: :secondary))
    end

    def delete
      render(UI::ActionComponent.new(type: :delete, label: "Delete", url: "#", confirm: "Are you sure?"))
    end

    def dialog
      render(UI::ActionComponent.new(
        type: :dialog, label: "Archive", dialog_title: "Archive this record?",
        url: "#", method: :post, confirm_label: "Archive", variant: :neutral
      ))
    end
  end
end
