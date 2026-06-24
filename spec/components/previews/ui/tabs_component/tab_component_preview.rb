# frozen_string_literal: true

module UI
  class TabsComponent
    class TabComponentPreview < ViewComponent::Preview
      def active
        render(UI::TabsComponent::TabComponent.new(
          id: "tab-one", label: "Overview", controls: "panel-one", active: true
        ))
      end

      def inactive
        render(UI::TabsComponent::TabComponent.new(
          id: "tab-two", label: "Settings", controls: "panel-two", active: false
        ))
      end
    end
  end
end
