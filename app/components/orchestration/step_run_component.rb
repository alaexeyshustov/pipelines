# frozen_string_literal: true

module Orchestration
  class StepRunComponent < ViewComponent::Base
    with_collection_parameter :entry

    renders_one :status_badge, -> { Orchestration::RunStatusBadgeComponent.new(status: @derived_status) }
    renders_many :action_run_items, Orchestration::ActionRunComponent

    def initialize(entry:)
      @step = entry[:step]
      @action_run_records = entry[:action_runs]
      @derived_status = entry[:derived_status]
    end

    def before_render
      with_status_badge
      @action_run_records.each { |ar| with_action_run_item(action_run: ar) }
    end
  end
end
