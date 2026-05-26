# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Improvement::ListExperimentsTool do
  subject(:tool) { described_class.new }

  let(:prompt_name) { "Emails::ClassifyAgent" }
  let(:prompt) { create(:orchestration_prompt, name: prompt_name) }
  let(:current_experiment) { create(:evaluation_experiment, status: :completed, prompt: prompt) }

  def result_with_justification(experiment, metric_name:, score:, justification: "good")
    result = create(:evaluation_evaluation_result, experiment: experiment, score: score)
    create(:evaluation_justification, evaluation_result: result, metric_name: metric_name, justification: justification)
  end

  describe "#execute" do
    it "returns empty array when no other completed experiments exist" do
      expect(tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)).to eq([])
    end

    it "excludes the current experiment" do
      result_with_justification(current_experiment, metric_name: "accuracy", score: 4.0)
      expect(tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)).to be_empty
    end

    it "excludes failed experiments" do
      create(:evaluation_experiment, status: :failed, prompt: prompt)
      expect(tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)).to be_empty
    end

    it "excludes experiments for other agents" do
      other_prompt = create(:orchestration_prompt, name: "OtherAgent")
      create(:evaluation_experiment, status: :completed, prompt: other_prompt)
      expect(tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)).to be_empty
    end

    context "with a past completed experiment" do
      let(:metric) { create(:evaluation_metric, agent_name: prompt_name, name: "accuracy", weight: 1.0) }
      let(:past_experiment) { create(:evaluation_experiment, status: :completed, prompt: prompt) }

      before do
        metric
        result_with_justification(past_experiment, metric_name: "accuracy", score: 3.0)
      end

      it "returns correct structure" do
        results = tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)

        expect(results.size).to eq(1)
        expect(results.first).to include(
          experiment_id: past_experiment.id,
          prompt_version: past_experiment.prompt.version,
          per_metric_averages: { "accuracy" => 3.0 },
          overall_average: 3.0
        )
        expect(results.first[:date]).to be_a(String)
      end

      it "computes weighted overall average across metrics" do
        create(:evaluation_metric, agent_name: prompt_name, name: "clarity", weight: 3.0)
        result_with_justification(past_experiment, metric_name: "clarity", score: 5.0)

        results = tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)
        # accuracy: 3.0 * 1.0, clarity: 5.0 * 3.0 → (3+15)/4 = 4.5
        expect(results.first[:overall_average]).to eq(4.5)
      end

      it "orders results by created_at ascending" do
        later_prompt = create(:orchestration_prompt, name: prompt_name)
        later_experiment = create(:evaluation_experiment, status: :completed, prompt: later_prompt)
        result_with_justification(later_experiment, metric_name: "accuracy", score: 4.0)

        results = tool.execute(prompt_name: prompt_name, current_experiment_id: current_experiment.id)
        ids = results.map { |r| r[:experiment_id] }
        expect(ids).to eq([ past_experiment.id, later_experiment.id ])
      end
    end
  end
end
