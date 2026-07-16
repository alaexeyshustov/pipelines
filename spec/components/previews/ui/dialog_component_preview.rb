
module UI
  class DialogComponentPreview < ViewComponent::Preview
    def danger
      render(UI::DialogComponent.new(label: "Delete", dialog_title: "Delete this record?", variant: :danger))
    end

    def neutral
      render(UI::DialogComponent.new(label: "Archive", dialog_title: "Archive this record?", variant: :neutral))
    end

    def primary
      render(UI::DialogComponent.new(label: "Confirm", dialog_title: "Confirm action?", variant: :primary))
    end
  end
end
