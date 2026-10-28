module UI
  class LabelComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/label_component_preview/default")
    end
  end
end
