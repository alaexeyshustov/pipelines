module UI
  class FormFieldComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/form_field_component_preview/default")
    end
  end
end
