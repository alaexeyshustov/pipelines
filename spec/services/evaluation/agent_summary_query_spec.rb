# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::AgentSummaryQuery do
  describe ".call" do
    context "when no experiments exist" do
      it "returns an empty array" do
        expect(described_class.call).to eq([])
      end
    end

    context "when experiments exist for multiple agents" do
      let(:prompt_a) { create(:orchestration_prompt, name: "AgentA") }
      let(:prompt_b) { create(:orchestration_prompt, name: "AgentB") }

      before do
        create(:evaluation_experiment, prompt: prompt_a, status: :completed)
        create(:evaluation_experiment, prompt: prompt_b, status: :completed)
      end

      it "returns one AgentSummary per agent name" do
        result = described_class.call
        expect(result.size).to eq(2)
        expect(result).to all(be_a(Evaluation::AgentSummaryQuery::AgentSummary))
      end

      it "sets agent_name correctly" do
        result = described_class.call
        expect(result.map(&:agent_name)).to contain_exactly("AgentA", "AgentB")
      end

      it "sets latest_experiment to the most recent experiment for each agent" do
        later_exp_a = create(:evaluation_experiment, prompt: prompt_a, status: :completed)
        result = described_class.call
        summary_a = result.find { |s| s.agent_name == "AgentA" }
        expect(summary_a.latest_experiment).to eq(later_exp_a)
      end
    end

    context "when experiments have evaluation results" do
      let(:prompt) { create(:orchestration_prompt, name: "ScoredAgent") }
      let!(:exp)   { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      before do
        runner_result = create(:evaluation_runner_result, experiment: exp)
        create(:evaluation_evaluation_result,
          experiment: exp,
          runner_result: runner_result,
          dataset_record: runner_result.dataset_record,
          score: 3.0)
        create(:evaluation_evaluation_result,
          experiment: exp,
          runner_result: runner_result,
          dataset_record: runner_result.dataset_record,
          score: 5.0)
      end

      it "populates latest_score as the rounded average" do
        summary = described_class.call.first
        expect(summary.latest_score).to eq(4.0)
      end

      it "populates sample_count with the number of results" do
        summary = described_class.call.first
        expect(summary.sample_count).to eq(2)
      end

      it "builds score_history entries for each experiment" do
        summary = described_class.call.first
        expect(summary.score_history.size).to eq(1)
        entry = summary.score_history.first
        expect(entry[:created_at]).to eq(exp.created_at.strftime("%Y-%m-%d"))
        expect(entry[:avg_score]).to eq(4.0)
      end
    end

    context "when no evaluation results exist" do
      let(:prompt) { create(:orchestration_prompt, name: "EmptyAgent") }

      before { create(:evaluation_experiment, prompt: prompt, status: :pending) }

      it "returns latest_score as nil" do
        summary = described_class.call.first
        expect(summary.latest_score).to be_nil
      end

      it "returns sample_count as 0" do
        summary = described_class.call.first
        expect(summary.sample_count).to eq(0)
      end
    end

    context "when a prompt has an active version in metadata" do
      let(:prompt) { create(:orchestration_prompt, name: "VersionedAgent", metadata: '{"active":true}') }

      before { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      it "populates active_prompt_version with the prompt version" do
        summary = described_class.call.first
        expect(summary.active_prompt_version).to eq(prompt.version)
      end
    end

    context "when a prompt has no active version" do
      let(:prompt) { create(:orchestration_prompt, name: "InactiveAgent", metadata: '{"active":false}') }

      before { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      it "returns active_prompt_version as nil" do
        summary = described_class.call.first
        expect(summary.active_prompt_version).to be_nil
      end
    end
  end
end
