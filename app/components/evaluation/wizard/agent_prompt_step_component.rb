# frozen_string_literal: true

module Evaluation
  module Wizard
    class AgentPromptStepComponent < ViewComponent::Base
      def initialize(form:)
        @form = form
      end

      def agent_names      = @form.agent_names
      def prompts          = @form.prompts
      def agent_name       = @form.agent_name
      def prompt_id        = @form.prompt_id
      def experiment_name  = @form.experiment_name
      def available_models = @form.available_models
      def sample_model     = @form.sample_model
      def evaluation_model = @form.evaluation_model

      def snapshot_url
        helpers.snapshot_agent_prompt_evaluation_experiments_path
      end

      def fork_prompt_url
        helpers.fork_prompt_evaluation_experiments_path
      end

      def prompt_content_url
        helpers.prompt_content_evaluation_experiments_path
      end

      def prompt_options
        prompts.map { |p| [ "#{p.name} v#{p.version}", p.id ] }
      end

      def model_options
        available_models.flat_map do |provider, models|
          models.map { |m| [ "#{provider} / #{m}", m ] }
        end
      end
    end
  end
end
