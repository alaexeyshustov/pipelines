# frozen_string_literal: true

module Evaluation
  module ExperimentWizard
    extend ActiveSupport::Concern

    private

    def build_wizard_form(step_param: nil)
      token = session[:wizard_token] ||= SecureRandom.hex(16)
      WizardForm.new(wizard_token: token, step_param: step_param)
    end

    def fork_prompt_params
      params.permit(:based_on_prompt_id, :system_prompt, :user_prompt, :output_schema)
    end

    def wizard_params
      params.fetch(:wizard, {}).permit(:agent_name, :prompt_id, :experiment_name, :sample_model, :evaluation_model, :dataset_id).to_h
    end

    def complete_wizard_or_error
      if @wizard_form.valid?
        experiment = @wizard_form.complete!
        session.delete(:wizard_token)
        redirect_to evaluation_experiment_path(experiment), notice: "Experiment '#{experiment.name}' started."
      else
        render_wizard_error
      end
    end

    def advance_wizard_or_error
      if @wizard_form.advance!(@wizard_form.step, wizard_params)
        redirect_to new_evaluation_experiment_path(step: @wizard_form.step + 1)
      else
        render_wizard_error
      end
    end

    def fork_prompt_record(based_on)
      Evaluation::Prompt.create!(
        name: based_on.name,
        system_prompt: fork_prompt_params[:system_prompt] || based_on.system_prompt,
        user_prompt:   fork_prompt_params[:user_prompt]   || based_on.user_prompt,
        output_schema: fork_prompt_params[:output_schema] || based_on.output_schema
      )
    end

    def render_wizard_error
      flash.now[:alert] = @wizard_form.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end
end
