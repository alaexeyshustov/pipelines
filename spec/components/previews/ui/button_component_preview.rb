module UI
  class ButtonComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/button_component_preview/default")
    end
  end
end
