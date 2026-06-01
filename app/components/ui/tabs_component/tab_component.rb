# frozen_string_literal: true

module UI
  class TabsComponent
    class TabComponent < ViewComponent::Base
      def initialize(id:, label:, controls:, active: false)
        @id       = id
        @label    = label
        @controls = controls
        @active   = active
      end

      def call
        content_tag(
          :button,
          @label,
          type: "button",
          id: @id,
          role: "tab",
          aria: { selected: @active.to_s, controls: @controls },
          tabindex: @active ? "0" : "-1",
          data: { tabs_target: "tab", action: "click->tabs#show keydown->tabs#keydown" },
          class: tab_classes
        )
      end

      private

      def tab_classes
        base = "py-2 px-1 border-b-2 text-sm font-medium whitespace-nowrap"
        state = @active ? "border-indigo-600 text-indigo-600" : "border-transparent text-gray-500"
        "#{base} #{state}"
      end
    end
  end
end
