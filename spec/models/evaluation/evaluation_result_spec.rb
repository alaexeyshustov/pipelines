require "rails_helper"

RSpec.describe Evaluation::EvaluationResult do
  def make_eval_result(experiment:, score:, metric_name:)
    runner_result = create(:evaluation_runner_result, experiment: experiment)
    eval_result = create(:evaluation_evaluation_result,
      experiment: experiment,
      runner_result: runner_result,
      dataset_record: runner_result.dataset_record,
      score: score)
    create(:evaluation_justification, evaluation_result: eval_result, metric_name: metric_name)
    eval_result
  end

  let(:experiment) { create(:evaluation_experiment) }

  describe ".per_metric_averages" do
    context "when justifications exist for the experiment" do
      before do
        make_eval_result(experiment: experiment, score: 3.0, metric_name: "accuracy")
        make_eval_result(experiment: experiment, score: 5.0, metric_name: "accuracy")
        make_eval_result(experiment: experiment, score: 2.0, metric_name: "relevance")
      end

      it "returns a hash keyed by metric name" do
        result = described_class.per_metric_averages(experiment)
        expect(result.keys).to contain_exactly("accuracy", "relevance")
      end

      it "averages scores per metric name" do
        result = described_class.per_metric_averages(experiment)
        expect(result["accuracy"]).to be_within(0.001).of(4.0)
        expect(result["relevance"]).to be_within(0.001).of(2.0)
      end

      it "does not include results from other experiments" do
        other_experiment = create(:evaluation_experiment)
        make_eval_result(experiment: other_experiment, score: 1.0, metric_name: "accuracy")

        result = described_class.per_metric_averages(experiment)
        expect(result["accuracy"]).to be_within(0.001).of(4.0)
      end
    end

    context "when no justifications exist for the experiment" do
      it "returns an empty hash" do
        result = described_class.per_metric_averages(experiment)
        expect(result).to eq({})
      end
    end
  end
end
