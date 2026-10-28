module UI
  class InputComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/input_component_preview/default")
    end
  end
end
