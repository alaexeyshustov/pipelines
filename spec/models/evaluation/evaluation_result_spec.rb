require "rails_helper"

RSpec.describe Evaluation::EvaluationResult do
  def make_eval_result(experiment:, score:, metric_name:)
    dataset_sample = create(:evaluation_dataset_sample, dataset: experiment.dataset)
    sample = create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample)
    eval_result = create(:evaluation_evaluation_result,
      experiment: experiment,
      sample: sample,
      dataset_sample: dataset_sample,
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

  describe ".overall_average" do
    it "returns the average score across all results for the experiment" do
      make_eval_result(experiment: experiment, score: 3.0, metric_name: "accuracy")
      make_eval_result(experiment: experiment, score: 5.0, metric_name: "relevance")

      expect(described_class.overall_average(experiment)).to be_within(0.001).of(4.0)
    end

    it "ignores results from other experiments" do
      make_eval_result(experiment: experiment, score: 4.0, metric_name: "accuracy")
      other = create(:evaluation_experiment)
      make_eval_result(experiment: other, score: 1.0, metric_name: "accuracy")

      expect(described_class.overall_average(experiment)).to be_within(0.001).of(4.0)
    end

    it "returns nil when the experiment has no results" do
      expect(described_class.overall_average(experiment)).to be_nil
    end
  end
end
