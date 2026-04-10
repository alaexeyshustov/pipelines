# frozen_string_literal: true

module Interviews
  class StatusBadgeComponent < UI::StatusBadgeComponent
    STATUS_VARIANTS = {
      "pending_reply"     => :warning,
      "having_interviews" => :info,
      "rejected"          => :danger,
      "offer_received"    => :success
    }.freeze

    def initialize(status:)
      super(
        label: status&.humanize || "—",
        variant: STATUS_VARIANTS.fetch(status.to_s, :neutral)
      )
    end
  end
end
