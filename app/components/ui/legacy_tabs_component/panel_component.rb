module UI
  class LegacyTabsComponent
    class PanelComponent < ViewComponent::Base
      def initialize(id:, tab_id:, active: false)
        @id     = id
        @tab_id = tab_id
        @active = active
      end

      def call
        attrs = {
          id:   @id,
          role: "tabpanel",
          aria: { labelledby: @tab_id },
          data: { legacy_tabs_target: "panel" }
        }
        attrs[:hidden] = true unless @active
        content_tag(:div, content, **attrs)
      end
    end
  end
end
