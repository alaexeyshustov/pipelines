module UI
  class SearchInputComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/search_input_component_preview/default")
    end
  end
end
