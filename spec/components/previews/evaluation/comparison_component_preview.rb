module Evaluation
  class ComparisonComponentPreview < ViewComponent::Preview
    def default
      result = OpenStruct.new(
        metric_deltas: { "accuracy" => 0.025, "relevance" => -0.01, "coherence" => nil }
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
        metric_deltas: { "accuracy" => 0.05, "relevance" => 0.032, "coherence" => 0.018 }
      )
      render(Evaluation::ComparisonComponent.new(
        result: result,
        baseline_experiment: OpenStruct.new(name: "v1"),
        candidate_experiment: OpenStruct.new(name: "v2")
      ))
    end
  end
end
