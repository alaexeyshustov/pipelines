module UI
  class SelectComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/select_component_preview/default")
    end
  end
end
