module Pages
  # Fake-data page built from ViewPrimitives, rendered inside the real application layout.
  class PipelineShowPreview < ViewComponent::Preview
    layout "application"

    def default
      render_with_template(template: "pages/pipeline_show_preview/default")
    end
  end
end
