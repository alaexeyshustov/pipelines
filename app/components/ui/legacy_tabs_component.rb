module UI
  class LegacyTabsComponent < ViewComponent::Base
    renders_many :tabs, "UI::LegacyTabsComponent::TabComponent"
    renders_many :panels, "UI::LegacyTabsComponent::PanelComponent"

    def initialize(extra_controllers: [])
      @extra_controllers = Array(extra_controllers)
    end

    def controller_value
      ([ "legacy-tabs" ] + @extra_controllers).join(" ")
    end
  end
end
