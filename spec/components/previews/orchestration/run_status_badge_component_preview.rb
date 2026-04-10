# frozen_string_literal: true

module Orchestration
  class RunStatusBadgeComponentPreview < ViewComponent::Preview
    def completed
      render(Orchestration::RunStatusBadgeComponent.new(status: "completed"))
    end

    def running
      render(Orchestration::RunStatusBadgeComponent.new(status: "running"))
    end

    def failed
      render(Orchestration::RunStatusBadgeComponent.new(status: "failed"))
    end

    def pending
      render(Orchestration::RunStatusBadgeComponent.new(status: "pending"))
    end
  end
end
