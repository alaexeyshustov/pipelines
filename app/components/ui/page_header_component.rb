# frozen_string_literal: true

module UI
  class PageHeaderComponent < ViewComponent::Base
    renders_one  :badge, UI::StatusBadgeComponent
    renders_many :actions, UI::ActionComponent

    def initialize(title:, parent: nil, notice: nil, alert: nil)
      @title = title
      @parent = parent
      @notice = notice
      @alert = alert
    end
  end
end
