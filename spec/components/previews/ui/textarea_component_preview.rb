module UI
  class TextareaComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/textarea_component_preview/default")
    end
  end
end
