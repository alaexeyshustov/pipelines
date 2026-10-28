module UI
  class PaginationComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/pagination_component_preview/default")
    end
  end
end
