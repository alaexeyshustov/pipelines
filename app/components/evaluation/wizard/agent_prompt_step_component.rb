# frozen_string_literal: true

module Evaluation
  module Wizard
    class AgentPromptStepComponent < ViewComponent::Base
      def initialize(agent_names:, prompts:, agent_name: nil, prompt_id: nil, experiment_name: nil,
                     available_models: [], sample_model: nil, evaluation_model: nil)
        @agent_names       = agent_names
        @prompts           = prompts
        @agent_name        = agent_name
        @prompt_id         = prompt_id
        @experiment_name   = experiment_name
        @available_models  = available_models
        @sample_model      = sample_model
        @evaluation_model  = evaluation_model
      end

      def prompt_options
        @prompts.map { |p| [ "#{p.name} v#{p.version}", p.id ] }
      end

      def model_options
        @available_models.flat_map do |provider, models|
          models.map { |m| [ "#{provider} / #{m}", m ] }
        end
      end
    end
  end
end
