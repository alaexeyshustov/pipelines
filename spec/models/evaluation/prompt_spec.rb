require "rails_helper"

RSpec.describe Evaluation::Prompt do
  it "does not enqueue PromptAutoEvalJob on create or update (enqueue lives in Evaluation::PromptCreator)" do
    prompt = create(:orchestration_prompt)
    prompt.update!(system_prompt: "Updated prompt text")

    expect(Evaluation::PromptAutoEvalJob).not_to have_received(:perform_later)
  end

  it "increments the version for new prompts with the same name" do
    create(:orchestration_prompt, name: "Emails::ClassifyAgent")

    prompt = create(:orchestration_prompt, name: "Emails::ClassifyAgent")

    expect(prompt.version).to eq(2)
  end

  describe ".versions_for" do
    it "returns all versions for the name ordered by version desc" do
      v1 = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 1)
      v3 = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 3)
      v2 = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 2)
      create(:orchestration_prompt, name: "Other::Agent", version: 1)

      expect(described_class.versions_for("Emails::ClassifyAgent")).to eq([ v3, v2, v1 ])
    end
  end

  describe ".metadata_versions_for" do
    it "returns id, version and active for the name ordered by version desc" do
      v1 = create(:orchestration_prompt, :active, name: "Emails::ClassifyAgent", version: 1)
      v2 = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 2)

      result = described_class.metadata_versions_for("Emails::ClassifyAgent")

      expect(result.map(&:id)).to eq([ v2.id, v1.id ])
      expect(result.map(&:version)).to eq([ 2, 1 ])
      expect(result.map(&:active)).to eq([ false, true ])
    end
  end

  describe ".active_for_agent" do
    it "returns the active version, not the newest one" do
      active = create(:orchestration_prompt, :active, name: "AgentA", version: 1)
      create(:orchestration_prompt, name: "AgentA", version: 2)
      create(:orchestration_prompt, :active, name: "AgentB", version: 1)

      expect(described_class.active_for_agent("AgentA")).to eq(active)
    end

    it "returns nil when no version is active" do
      create(:orchestration_prompt, name: "AgentA", version: 1)

      expect(described_class.active_for_agent("AgentA")).to be_nil
    end
  end

  describe ".latest_for_agent" do
    it "returns the highest version, breaking ties by the highest id" do
      create(:orchestration_prompt, name: "AgentA", version: 1)
      create(:orchestration_prompt, name: "AgentA", version: 2)
      newest = create(:orchestration_prompt, name: "AgentA", version: 2)
      create(:orchestration_prompt, name: "AgentB", version: 9)

      expect(described_class.latest_for_agent("AgentA")).to eq(newest)
    end
  end

  describe ".effective_system_prompt_for" do
    it "returns the active version's system prompt, ignoring a newer inactive draft" do
      create(:orchestration_prompt, :active, name: "AgentA", version: 1, system_prompt: "active text")
      create(:orchestration_prompt, name: "AgentA", version: 2, system_prompt: "draft text")
      create(:orchestration_agent, name: "AgentA", prompt: "agent default")

      expect(described_class.effective_system_prompt_for("AgentA")).to eq("active text")
    end

    it "falls back to the agent's own prompt when no version is active" do
      create(:orchestration_prompt, name: "AgentA", version: 1, system_prompt: "draft text")
      create(:orchestration_agent, name: "AgentA", prompt: "agent default")

      expect(described_class.effective_system_prompt_for("AgentA")).to eq("agent default")
    end

    it "returns nil when nothing is active and the agent is unknown" do
      expect(described_class.effective_system_prompt_for("Unknown::Agent")).to be_nil
    end
  end

  describe "#activate!" do
    it "deactivates the previously active version and records activated_at" do
      v1 = create(:orchestration_prompt, :active, name: "AgentA", version: 1)
      create(:orchestration_prompt, name: "AgentA", version: 2)
      v3 = create(:orchestration_prompt, name: "AgentA", version: 3)

      v3.activate!

      expect(v1.reload.active).to be(false)
      expect(v3.reload).to have_attributes(active: true, activated_at: be_present)
      expect(described_class.where(name: "AgentA", active: true)).to contain_exactly(v3)
    end

    it "does not touch other agents' active versions" do
      other = create(:orchestration_prompt, :active, name: "AgentB", version: 1)
      prompt = create(:orchestration_prompt, name: "AgentA", version: 1)

      prompt.activate!

      expect(other.reload.active).to be(true)
    end
  end

  describe "#deactivate!" do
    it "clears active but keeps activated_at" do
      prompt = create(:orchestration_prompt, :active, name: "AgentA")
      stamped = prompt.activated_at

      prompt.deactivate!

      expect(prompt.reload.active).to be(false)
      expect(prompt.activated_at).to be_within(1.second).of(stamped)
    end

    it "is a no-op on an inactive version" do
      prompt = create(:orchestration_prompt, name: "AgentA", activated_at: 2.days.ago)
      stamped = prompt.reload.activated_at

      expect { prompt.deactivate! }.not_to(change { prompt.reload.attributes })
      expect(prompt.activated_at).to eq(stamped)
    end
  end

  describe "#activatable?" do
    it "is true when the version has a completed experiment" do
      prompt = create(:orchestration_prompt)
      create(:evaluation_experiment, prompt: prompt, status: :completed)

      expect(prompt).to be_activatable
    end

    it "is true when the version was activated before" do
      prompt = create(:orchestration_prompt, activated_at: 1.day.ago)

      expect(prompt).to be_activatable
    end

    it "is false for a fresh draft, even with a pending experiment" do
      prompt = create(:orchestration_prompt)
      create(:evaluation_experiment, prompt: prompt, status: :pending)

      expect(prompt).not_to be_activatable
    end
  end

  describe "#label" do
    it "is the version prefixed with v" do
      expect(build(:orchestration_prompt, version: 3).label).to eq("v3")
    end
  end

  describe "the one-active-per-name invariant" do
    it "rejects a second active row for the same name at the database level" do
      create(:orchestration_prompt, :active, name: "AgentA", version: 1)

      expect { create(:orchestration_prompt, :active, name: "AgentA", version: 2) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows one active row per distinct name" do
      create(:orchestration_prompt, :active, name: "AgentA")

      expect { create(:orchestration_prompt, :active, name: "AgentB") }.not_to raise_error
    end
  end

  describe ".other_versions_for" do
    it "excludes the given id and orders by version desc then id desc" do
      current = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 3)
      v2_low  = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 2)
      v2_high = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 2)
      v1      = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 1)
      create(:orchestration_prompt, name: "Other::Agent", version: 2)

      expect(v2_high.id).to be > v2_low.id

      result = described_class.other_versions_for("Emails::ClassifyAgent", excluding_id: current.id)

      expect(result).to eq([ v2_high, v2_low, v1 ])
    end
  end
end
