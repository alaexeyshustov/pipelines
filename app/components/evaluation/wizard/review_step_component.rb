# frozen_string_literal: true

module Evaluation
  module Wizard
    class ReviewStepComponent < ViewComponent::Base
      def initialize(agent_name:, prompt:, experiment_name:, metrics_count:, dataset:)
        @agent_name      = agent_name
        @prompt          = prompt
        @experiment_name = experiment_name
        @metrics_count   = metrics_count
        @dataset         = dataset
      end

      def no_metrics?
        @metrics_count.to_i.zero?
      end

      def prompt_label
        return "—" unless @prompt
        "#{@prompt.name} v#{@prompt.version}"
      end

      def dataset_label
        @dataset&.name || "—"
      end
    end
  end
end
