module UI
  class BreadcrumbComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/breadcrumb_component_preview/default")
    end
  end
end
