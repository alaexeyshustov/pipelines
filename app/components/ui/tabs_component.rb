
module UI
  class TabsComponent < ViewComponent::Base
    renders_many :tabs, "UI::TabsComponent::TabComponent"
    renders_many :panels, "UI::TabsComponent::PanelComponent"

    def initialize(extra_controllers: [])
      @extra_controllers = Array(extra_controllers)
    end

    def controller_value
      ([ "tabs" ] + @extra_controllers).join(" ")
    end
  end
end
