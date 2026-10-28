module UI
  class AlertComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/alert_component_preview/default")
    end
  end
end
