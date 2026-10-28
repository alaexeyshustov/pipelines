module UI
  class CardComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/card_component_preview/default")
    end
  end
end
