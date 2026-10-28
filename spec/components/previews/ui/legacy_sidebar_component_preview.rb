module UI
  class LegacySidebarComponentPreview < ViewComponent::Preview
    def default
      render(UI::LegacySidebarComponent.new(current_path: "/"))
    end

    def pipelines_active
      render(UI::LegacySidebarComponent.new(current_path: "/orchestration/pipelines"))
    end

    def evaluation_active
      render(UI::LegacySidebarComponent.new(current_path: "/evaluation"))
    end
  end
end
