require "rails_helper"

RSpec.describe Evaluation::Comparison do
  def make_eval_result(experiment:, score:, metric_name:)
    runner_result = create(:leva_runner_result, experiment: experiment)
    eval_result = create(:leva_evaluation_result,
      experiment: experiment,
      runner_result: runner_result,
      dataset_record: runner_result.dataset_record,
      score: score)
    create(:evaluation_justification, evaluation_result: eval_result, metric_name: metric_name)
    eval_result
  end

  let(:baseline)  { create(:leva_experiment, name: "baseline") }
  let(:candidate) { create(:leva_experiment, name: "candidate") }

  describe ".call" do
    context "when both experiments have the same metrics" do
      before do
        make_eval_result(experiment: baseline,  score: 3.0, metric_name: "accuracy")
        make_eval_result(experiment: baseline,  score: 2.0, metric_name: "relevance")
        make_eval_result(experiment: candidate, score: 4.0, metric_name: "accuracy")
        make_eval_result(experiment: candidate, score: 3.0, metric_name: "relevance")
      end

      it "returns a ComparisonResult" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result).to be_a(Evaluation::Comparison::ComparisonResult)
      end

      it "computes per-metric deltas (positive = improvement)" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.metric_deltas["accuracy"]).to be_within(0.001).of(1.0)
        expect(result.metric_deltas["relevance"]).to be_within(0.001).of(1.0)
      end

      it "computes baseline_score as overall average" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.baseline_score).to be_within(0.001).of(2.5)
      end

      it "computes candidate_score as overall average" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.candidate_score).to be_within(0.001).of(3.5)
      end

      it "computes overall_delta = candidate_score - baseline_score" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.overall_delta).to be_within(0.001).of(1.0)
      end
    end

    context "when candidate regresses on a metric" do
      before do
        make_eval_result(experiment: baseline,  score: 4.0, metric_name: "accuracy")
        make_eval_result(experiment: candidate, score: 2.0, metric_name: "accuracy")
      end

      it "reports a negative delta for that metric" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.metric_deltas["accuracy"]).to be_within(0.001).of(-2.0)
      end
    end

    context "when metrics differ between experiments" do
      before do
        make_eval_result(experiment: baseline,  score: 3.0, metric_name: "accuracy")
        make_eval_result(experiment: candidate, score: 4.0, metric_name: "accuracy")
        make_eval_result(experiment: baseline,  score: 2.0, metric_name: "only_in_baseline")
        make_eval_result(experiment: candidate, score: 5.0, metric_name: "only_in_candidate")
      end

      it "includes all metrics in metric_deltas" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.metric_deltas.keys).to contain_exactly("accuracy", "only_in_baseline", "only_in_candidate")
      end

      it "sets nil delta for metrics present only in one experiment" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.metric_deltas["only_in_baseline"]).to be_nil
        expect(result.metric_deltas["only_in_candidate"]).to be_nil
      end

      it "computes delta normally for shared metrics" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.metric_deltas["accuracy"]).to be_within(0.001).of(1.0)
      end
    end

    context "when a metric has multiple eval results" do
      before do
        make_eval_result(experiment: baseline,  score: 2.0, metric_name: "accuracy")
        make_eval_result(experiment: baseline,  score: 4.0, metric_name: "accuracy")
        make_eval_result(experiment: candidate, score: 3.0, metric_name: "accuracy")
        make_eval_result(experiment: candidate, score: 5.0, metric_name: "accuracy")
      end

      it "averages scores per metric before computing delta" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.metric_deltas["accuracy"]).to be_within(0.001).of(1.0)
      end
    end

    context "when one experiment has no evaluation results" do
      before do
        make_eval_result(experiment: baseline, score: 3.0, metric_name: "accuracy")
      end

      it "returns nil for candidate_score" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.candidate_score).to be_nil
      end

      it "returns nil for overall_delta" do
        result = described_class.call(baseline_experiment: baseline, candidate_experiment: candidate)
        expect(result.overall_delta).to be_nil
      end
    end
  end
end
