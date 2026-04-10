# frozen_string_literal: true

module Orchestration
  class RunStatusBadgeComponent < UI::StatusBadgeComponent
    STATUS_VARIANTS = {
      "completed" => :success,
      "running"   => :info,
      "failed"    => :danger
    }.freeze

    def initialize(status:)
      super(
        label: status.to_s.capitalize,
        variant: STATUS_VARIANTS.fetch(status.to_s, :neutral)
      )
    end
  end
end
