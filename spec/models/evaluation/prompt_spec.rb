require "rails_helper"

RSpec.describe Evaluation::Prompt do
  it "enqueues PromptAutoEvalJob when a new prompt is created" do
    prompt = create(:orchestration_prompt)
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: prompt.id)
  end

  it "does not enqueue PromptAutoEvalJob when an existing prompt is updated" do
    prompt = create(:orchestration_prompt)
    original_version = prompt.version

    prompt.update!(system_prompt: "Updated prompt text")

    # Exactly 1 call total (from create); update must not have triggered another
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).exactly(1).time
    expect(prompt.reload.version).to eq(original_version)
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
    it "returns id, version and metadata for the name ordered by version desc" do
      v1 = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 1)
      v2 = create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 2)

      result = described_class.metadata_versions_for("Emails::ClassifyAgent")

      expect(result.map(&:id)).to eq([ v2.id, v1.id ])
      expect(result.map(&:version)).to eq([ 2, 1 ])
    end
  end

  describe ".active_metadata_versions_for" do
    it "returns prompts for the given names whose metadata has active: true" do
      active = create(:orchestration_prompt, name: "AgentA", version: 1, metadata: '{"active":true}')
      create(:orchestration_prompt, name: "AgentA", version: 2, metadata: '{"active":false}')
      create(:orchestration_prompt, name: "AgentB", version: 1, metadata: '{"active":true}')

      expect(described_class.active_metadata_versions_for([ "AgentA" ])).to eq([ active ])
    end

    it "matches across multiple agent names" do
      a = create(:orchestration_prompt, name: "AgentA", version: 1, metadata: '{"active":true}')
      b = create(:orchestration_prompt, name: "AgentB", version: 1, metadata: '{"active":true}')
      create(:orchestration_prompt, name: "AgentC", version: 1, metadata: '{"active":true}')

      expect(described_class.active_metadata_versions_for([ "AgentA", "AgentB" ])).to contain_exactly(a, b)
    end

    # Byte-identical SQL guarantees the extraction is a pure no-op vs. the original
    # inline query in Evaluation::AgentSummaryQuery#fetch_active_prompts.
    describe "generated SQL" do
      let(:names) { [ "AgentA", "AgentB" ] }
      let(:baseline_where_only) do
        %(SELECT "evaluation_prompts".* FROM "evaluation_prompts" WHERE "evaluation_prompts"."name" IN ('AgentA', 'AgentB') AND (json_extract(metadata, '$.active') = TRUE))
      end
      let(:baseline_full) do
        %(SELECT "evaluation_prompts".* FROM "evaluation_prompts" WHERE "evaluation_prompts"."name" IN ('AgentA', 'AgentB') AND (json_extract(metadata, '$.active') = TRUE) ORDER BY "evaluation_prompts"."version" DESC)
      end

      it "matches the original WHERE clause byte-for-byte" do
        expect(described_class.active_metadata_versions_for(names).to_sql).to eq(baseline_where_only)
      end

      it "reproduces the original full query when chained with the preserved order" do
        expect(described_class.active_metadata_versions_for(names).order(version: :desc).to_sql).to eq(baseline_full)
      end
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
