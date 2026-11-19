require "rails_helper"

RSpec.describe Evaluation::AgentSummaryQuery do
  describe ".call" do
    context "when no experiments exist" do
      it "returns an empty array" do
        expect(described_class.call.summaries).to eq([])
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
        result = described_class.call.summaries
        expect(result.size).to eq(2)
        expect(result).to all(be_a(Evaluation::AgentSummaryQuery::AgentSummary))
      end

      it "sets agent_name correctly" do
        result = described_class.call.summaries
        expect(result.map(&:agent_name)).to contain_exactly("AgentA", "AgentB")
      end

      it "sets latest_experiment to the most recent experiment for each agent" do
        later_exp_a = create(:evaluation_experiment, prompt: prompt_a, status: :completed)
        result = described_class.call.summaries
        summary_a = result.find { |s| s.agent_name == "AgentA" }
        expect(summary_a.latest_experiment).to eq(later_exp_a)
      end
    end

    context "when experiments have evaluation results" do
      let(:prompt) { create(:orchestration_prompt, name: "ScoredAgent") }
      let!(:exp)   { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      before do
        dataset_sample = create(:evaluation_dataset_sample, dataset: exp.dataset)
        sample = create(:evaluation_sample, experiment: exp, dataset_sample: dataset_sample)
        create(:evaluation_evaluation_result, experiment: exp, sample: sample, dataset_sample: dataset_sample, score: 0.6)
        create(:evaluation_evaluation_result, experiment: exp, sample: sample, dataset_sample: dataset_sample, score: 1.0)
      end

      it "populates latest_score as the rounded average" do
        summary = described_class.call.summaries.first
        expect(summary.latest_score).to eq(0.8)
      end

      it "populates sample_count with the number of results" do
        summary = described_class.call.summaries.first
        expect(summary.sample_count).to eq(2)
      end

      it "builds score_history entries for each experiment" do
        summary = described_class.call.summaries.first
        expect(summary.score_history.size).to eq(1)
        entry = summary.score_history.first
        expect(entry[:created_at]).to eq(exp.created_at.strftime("%Y-%m-%d"))
        expect(entry[:avg_score]).to eq(0.8)
      end
    end

    context "when no evaluation results exist" do
      let(:prompt) { create(:orchestration_prompt, name: "EmptyAgent") }

      before { create(:evaluation_experiment, prompt: prompt, status: :pending) }

      it "returns latest_score as nil" do
        summary = described_class.call.summaries.first
        expect(summary.latest_score).to be_nil
      end

      it "returns sample_count as 0" do
        summary = described_class.call.summaries.first
        expect(summary.sample_count).to eq(0)
      end
    end

    context "when a prompt is the active version" do
      let(:prompt) { create(:orchestration_prompt, :active, name: "VersionedAgent") }

      before { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      it "populates active_prompt_version with the prompt version" do
        summary = described_class.call.summaries.first
        expect(summary.active_prompt_version).to eq(prompt.version)
      end
    end

    context "when the agent has no active version" do
      let(:prompt) { create(:orchestration_prompt, name: "InactiveAgent") }

      before { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      it "returns active_prompt_version as nil" do
        summary = described_class.call.summaries.first
        expect(summary.active_prompt_version).to be_nil
      end
    end

    context "when only a legacy metadata flag says active" do
      let(:prompt) { create(:orchestration_prompt, name: "LegacyAgent", metadata: '{"active":true}') }

      before { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      it "ignores the metadata and returns active_prompt_version as nil" do
        expect(described_class.call.summaries.first.active_prompt_version).to be_nil
      end
    end

    context "when a newer inactive version exists beside the active one" do
      let(:active) { create(:orchestration_prompt, :active, name: "TwoVersions", version: 1) }

      before do
        create(:orchestration_prompt, name: "TwoVersions", version: 2)
        create(:evaluation_experiment, prompt: active, status: :completed)
      end

      it "reports the active version, not the newest" do
        expect(described_class.call.summaries.first.active_prompt_version).to eq(1)
      end
    end
  end

  describe "#fetch_active_prompts" do
    subject(:fetched) { described_class.new.send(:fetch_active_prompts, [ "AgentA" ]) }

    it "returns the active version of the requested agents" do
      active = create(:orchestration_prompt, :active, name: "AgentA", version: 1)
      create(:orchestration_prompt, name: "AgentA", version: 2)
      expect(fetched).to eq([ active ])
    end

    it "excludes agents that have no active version" do
      create(:orchestration_prompt, name: "AgentA", version: 1)
      expect(fetched).to eq([])
    end

    it "does not read the metadata column, so malformed metadata is harmless" do
      create(:orchestration_prompt, name: "AgentA", version: 1, metadata: "not-json")
      expect { fetched }.not_to raise_error
    end

    it "excludes prompts for other agent names even when active" do
      create(:orchestration_prompt, :active, name: "AgentB", version: 1)
      expect(fetched).to eq([])
    end
  end
end
