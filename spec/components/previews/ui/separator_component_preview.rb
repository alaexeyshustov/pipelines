module UI
  class SeparatorComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/separator_component_preview/default")
    end
  end
end
