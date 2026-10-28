module UI
  class SidebarComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/sidebar_component_preview/default")
    end
  end
end
