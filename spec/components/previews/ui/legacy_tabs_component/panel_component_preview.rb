module UI
  class LegacyTabsComponent
    class PanelComponentPreview < ViewComponent::Preview
      def active
        render(UI::LegacyTabsComponent::PanelComponent.new(
          id: "panel-one", tab_id: "tab-one", active: true
        ).with_content("This panel is visible."))
      end

      def hidden
        render(UI::LegacyTabsComponent::PanelComponent.new(
          id: "panel-two", tab_id: "tab-two", active: false
        ).with_content("This panel is hidden."))
      end
    end
  end
end
