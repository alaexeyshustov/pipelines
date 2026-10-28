module Pages
  # Fake-data page built from ViewPrimitives, rendered inside the real application layout.
  class AgentFormPreview < ViewComponent::Preview
    layout "application"

    def default
      render_with_template(template: "pages/agent_form_preview/default")
    end
  end
end
