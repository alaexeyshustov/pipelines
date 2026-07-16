module Evaluation
  module Wizard
    class ReviewStepComponent < ViewComponent::Base
      def initialize(form:)
        @form = form
      end

      def agent_name      = @form.agent_name
      def prompt          = @form.prompt
      def experiment_name = @form.experiment_name
      def metrics_count   = @form.metrics_count
      def dataset         = @form.dataset

      def no_metrics?
        metrics_count.to_i.zero?
      end

      def prompt_label
        return "—" unless prompt
        "#{prompt.name} v#{prompt.version}"
      end

      def dataset_label
        dataset&.name || "—"
      end
    end
  end
end
