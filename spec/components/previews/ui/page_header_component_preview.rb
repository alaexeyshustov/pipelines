
module UI
  class PageHeaderComponentPreview < ViewComponent::Preview
    def default
      render(UI::PageHeaderComponent.new(title: "Pipelines"))
    end

    def with_parent
      render(UI::PageHeaderComponent.new(
        title: "My Pipeline",
        parent: { label: "Pipelines", url: "#" }
      ))
    end

    def with_notice
      render(UI::PageHeaderComponent.new(title: "Pipelines", notice: "Pipeline saved successfully."))
    end

    def with_actions
      render(UI::PageHeaderComponent.new(title: "Pipelines")) do |h|
        h.with_action(type: :link, label: "New Pipeline", url: "#", variant: :primary)
      end
    end
  end
end
