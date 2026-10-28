module Pages
  # Fake-data page built from ViewPrimitives, rendered inside the real application layout.
  class ModelsIndexPreview < ViewComponent::Preview
    layout "application"

    def default
      render_with_template(template: "pages/models_index_preview/default")
    end
  end
end
