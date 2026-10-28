module UI
  class CheckboxComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/checkbox_component_preview/default")
    end
  end
end
