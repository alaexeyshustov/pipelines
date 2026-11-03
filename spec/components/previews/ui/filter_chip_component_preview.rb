module UI
  class FilterChipComponentPreview < ViewComponent::Preview
    def default
      render(UI::FilterChipComponent.new(label: "bank", href: "#"))
    end

    def active
      render(UI::FilterChipComponent.new(label: "bank", href: "#", active: true))
    end
  end
end
