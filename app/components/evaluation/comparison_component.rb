module Evaluation
  class ComparisonComponent < ViewComponent::Base
    def initialize(result:, baseline_experiment:, candidate_experiment:)
      @result = result
      @baseline_experiment = baseline_experiment
      @candidate_experiment = candidate_experiment
    end

    def metric_names
      @result.metric_deltas.keys.sort
    end

    def delta_class(delta)
      return "text-gray-400" if delta.nil?
      delta >= 0 ? "text-green-600 font-medium" : "text-red-600 font-medium"
    end

    def format_delta(delta)
      return "—" if delta.nil?
      prefix = delta >= 0 ? "+" : ""
      "#{prefix}#{delta.round(1)}"
    end

    def format_score(score)
      return "—" if score.nil?
      score.round(1).to_s
    end
  end
end
