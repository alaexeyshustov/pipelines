module UI
  class LegacyDialogComponentPreview < ViewComponent::Preview
    def danger
      render(UI::LegacyDialogComponent.new(label: "Delete", dialog_title: "Delete this record?", variant: :danger))
    end

    def neutral
      render(UI::LegacyDialogComponent.new(label: "Archive", dialog_title: "Archive this record?", variant: :neutral))
    end

    def primary
      render(UI::LegacyDialogComponent.new(label: "Confirm", dialog_title: "Confirm action?", variant: :primary))
    end
  end
end
