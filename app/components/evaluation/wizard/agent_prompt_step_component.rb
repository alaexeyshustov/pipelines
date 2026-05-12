# frozen_string_literal: true

module Evaluation
  module Wizard
    class AgentPromptStepComponent < ViewComponent::Base
      def initialize(agent_names:, prompts:, agent_name: nil, prompt_id: nil, experiment_name: nil)
        @agent_names     = agent_names
        @prompts         = prompts
        @agent_name      = agent_name
        @prompt_id       = prompt_id
        @experiment_name = experiment_name
      end

      def prompt_options
        @prompts.map { |p| [ "#{p.name} v#{p.version}", p.id ] }
      end
    end
  end
end
