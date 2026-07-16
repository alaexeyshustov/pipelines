
require "rails_helper"

RSpec.describe Evaluation::Improvement::GetExperimentJustificationsTool do
  subject(:tool) { described_class.new }

  let(:experiment) { create(:evaluation_experiment, status: :completed) }

  describe "#execute" do
    it "returns an empty array when the experiment has no justifications" do
      expect(tool.execute(experiment_id: experiment.id)).to eq([])
    end

    context "with one justification" do
      let(:eval_result) { create(:evaluation_evaluation_result, experiment: experiment, score: 4.0) }

      before do
        create(:evaluation_justification,
               evaluation_result: eval_result,
               metric_name: "accuracy",
               justification: "Correct tool called")
      end

      it "returns justification tuples with metric_name, score, and justification" do
        output = tool.execute(experiment_id: experiment.id)
        expect(output.size).to eq(1)
        expect(output.first).to eq(metric_name: "accuracy", score: 4.0, justification: "Correct tool called")
      end
    end

    it "returns all justifications across multiple results and metrics" do
      result1 = create(:evaluation_evaluation_result, experiment: experiment, score: 3.0)
      result2 = create(:evaluation_evaluation_result, experiment: experiment, score: 5.0)
      create(:evaluation_justification, evaluation_result: result1, metric_name: "accuracy", justification: "ok")
      create(:evaluation_justification, evaluation_result: result2, metric_name: "clarity", justification: "clear")

      output = tool.execute(experiment_id: experiment.id)

      expect(output.size).to eq(2)
      metric_names = output.pluck(:metric_name)
      expect(metric_names).to contain_exactly("accuracy", "clarity")
    end

    it "does not include justifications from other experiments" do
      other_experiment = create(:evaluation_experiment, status: :completed)
      other_result = create(:evaluation_evaluation_result, experiment: other_experiment, score: 5.0)
      create(:evaluation_justification, evaluation_result: other_result, metric_name: "accuracy", justification: "irrelevant")

      expect(tool.execute(experiment_id: experiment.id)).to be_empty
    end
  end
end
