# frozen_string_literal: true

module Evaluation
  class WizardComponent < ViewComponent::Base
    def initialize(current_step:, form:)
      @current_step = current_step
      @form = form
    end

    private

    def step_content_component
      sf = @form.step_form(@current_step)
      case @current_step
      when 1
        Evaluation::Wizard::AgentPromptStepComponent.new(
          agent_names:      sf.agent_names,
          prompts:          sf.prompts,
          agent_name:       sf.agent_name,
          prompt_id:        sf.prompt_id,
          experiment_name:  sf.experiment_name,
          available_models: sf.available_models,
          sample_model:     sf.sample_model,
          evaluation_model: sf.evaluation_model
        )
      when 2
        Evaluation::Wizard::MetricsStepComponent.new(
          agent_name: sf.agent_name,
          metrics:    sf.metrics
        )
      when 3
        Evaluation::Wizard::DatasetStepComponent.new(
          agent_name:          sf.agent_name,
          datasets:            sf.datasets,
          selected_dataset_id: sf.selected_dataset_id,
          draft_token:         sf.draft_token
        )
      when 4
        Evaluation::Wizard::ReviewStepComponent.new(
          agent_name:      sf.agent_name,
          prompt:          sf.prompt,
          experiment_name: sf.experiment_name,
          metrics_count:   sf.metrics_count,
          dataset:         sf.dataset
        )
      end
    end
  end
end
