# frozen_string_literal: true

module Evaluation
  class WizardComponent < ViewComponent::Base
    renders_one :step_nav,    -> { Evaluation::Wizard::StepNavComponent.new(current_step: @current_step) }
    renders_one :prompts_step, -> { Evaluation::Wizard::AgentPromptStepComponent.new(form: @form.step_form(@current_step)) }
    renders_one :metrics_step, -> { Evaluation::Wizard::MetricsStepComponent.new(form: @form.step_form(@current_step)) }
    renders_one :dataset_step, -> { Evaluation::Wizard::DatasetStepComponent.new(form: @form.step_form(@current_step)) }
    renders_one :review_step,  -> { Evaluation::Wizard::ReviewStepComponent.new(form: @form.step_form(@current_step)) }

    def initialize(current_step:, form:)
      @current_step = current_step
      @form = form
    end

    def before_render
      with_step_nav
      case @current_step
      when 1 then with_prompts_step
      when 2 then with_metrics_step
      when 3 then with_dataset_step
      when 4 then with_review_step
      end
    end
  end
end
