# frozen_string_literal: true

module Interviews
  class StatusBadgeComponentPreview < ViewComponent::Preview
    def pending_reply
      render(Interviews::StatusBadgeComponent.new(status: "pending_reply"))
    end

    def having_interviews
      render(Interviews::StatusBadgeComponent.new(status: "having_interviews"))
    end

    def rejected
      render(Interviews::StatusBadgeComponent.new(status: "rejected"))
    end

    def offer_received
      render(Interviews::StatusBadgeComponent.new(status: "offer_received"))
    end

    def unknown_status
      render(Interviews::StatusBadgeComponent.new(status: nil))
    end
  end
end
