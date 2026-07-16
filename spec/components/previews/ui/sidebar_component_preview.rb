
module UI
  class SidebarComponentPreview < ViewComponent::Preview
    def default
      render(UI::SidebarComponent.new(current_path: "/"))
    end

    def pipelines_active
      render(UI::SidebarComponent.new(current_path: "/orchestration/pipelines"))
    end

    def evaluation_active
      render(UI::SidebarComponent.new(current_path: "/evaluation"))
    end
  end
end
