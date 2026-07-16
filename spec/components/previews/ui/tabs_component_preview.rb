
module UI
  class TabsComponentPreview < ViewComponent::Preview
    def default
      render(UI::TabsComponent.new) do |tabs|
        tabs.with_tab(id: "tab-overview", label: "Overview", controls: "panel-overview", active: true)
        tabs.with_tab(id: "tab-details",  label: "Details",  controls: "panel-details")
        tabs.with_panel(id: "panel-overview", tab_id: "tab-overview", active: true) { "Overview content" }
        tabs.with_panel(id: "panel-details",  tab_id: "tab-details")               { "Details content" }
      end
    end
  end
end
