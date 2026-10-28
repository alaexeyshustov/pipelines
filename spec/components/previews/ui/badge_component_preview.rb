module UI
  class BadgeComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/badge_component_preview/default")
    end
  end
end
