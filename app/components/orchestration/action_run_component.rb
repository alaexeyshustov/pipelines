# frozen_string_literal: true

module Orchestration
  class ActionRunComponent < ViewComponent::Base
    with_collection_parameter :action_run

    renders_one :status_badge, -> { Orchestration::RunStatusBadgeComponent.new(status: @action_run.status) }
    renders_one :diagnostics_disclosure, -> { UI::JsonDisclosureComponent.new(label: "Diagnostics", data: diagnostics_data) }
    renders_one :input_disclosure, -> { UI::JsonDisclosureComponent.new(label: "Input", data: @action_run.input) }
    renders_one :output_disclosure, -> { UI::JsonDisclosureComponent.new(label: "Output", data: @action_run.output) }

    def initialize(action_run:)
      @action_run = action_run
    end

    def before_render
      with_status_badge
      with_diagnostics_disclosure if diagnostics_data.present?
      with_input_disclosure
      with_output_disclosure
    end

    def action_name
      @action_run.step_action.action.name
    end

    def formatted_started_at
      @action_run.started_at&.strftime("%H:%M:%S")
    end

    def formatted_finished_at
      @action_run.finished_at&.strftime("%H:%M:%S")
    end

    def diagnostics_data
      return if @action_run.error_details.blank?

      @action_run.error_details.except("raw_response_excerpt").compact_blank
    end

    def raw_response_excerpt
      @action_run.error_details&.dig("raw_response_excerpt")
    end
  end
end
