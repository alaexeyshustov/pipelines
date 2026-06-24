# frozen_string_literal: true

module Evaluation
  class ComparisonComponentPreview < ViewComponent::Preview
    def default
      result = OpenStruct.new(
        metric_deltas: { "accuracy" => 2.5, "relevance" => -1.0, "coherence" => nil }
      )
      baseline = OpenStruct.new(name: "Experiment A")
      candidate = OpenStruct.new(name: "Experiment B")

      render(Evaluation::ComparisonComponent.new(
        result: result,
        baseline_experiment: baseline,
        candidate_experiment: candidate
      ))
    end

    def all_wins
      result = OpenStruct.new(
        metric_deltas: { "accuracy" => 5.0, "relevance" => 3.2, "coherence" => 1.8 }
      )
      render(Evaluation::ComparisonComponent.new(
        result: result,
        baseline_experiment: OpenStruct.new(name: "v1"),
        candidate_experiment: OpenStruct.new(name: "v2")
      ))
    end
  end
end
