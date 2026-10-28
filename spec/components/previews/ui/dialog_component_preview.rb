module UI
  class DialogComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/dialog_component_preview/default")
    end
  end
end
