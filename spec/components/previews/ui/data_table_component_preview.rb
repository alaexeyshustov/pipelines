module UI
  class DataTableComponentPreview < ViewComponent::Preview
    layout "primitive_preview"

    def default
      render_with_template(template: "ui/data_table_component_preview/default")
    end
  end
end
