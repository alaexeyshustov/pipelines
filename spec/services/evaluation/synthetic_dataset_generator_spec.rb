# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::SyntheticDatasetGenerator do
  describe ".call" do
    let(:draft_token)    { "tok_abc123" }
    let(:agent_name)     { "Emails::ClassifyAgent" }
    let(:dataset_name)   { "Synthetic emails v1" }
    let(:count)          { "5" }

    before do
      allow(Evaluation::SyntheticDatasetJob).to receive(:perform_later)
    end

    it "enqueues SyntheticDatasetJob with coerced integer count" do
      described_class.call(
        draft_token: draft_token,
        agent_name:  agent_name,
        dataset_name: dataset_name,
        count: count
      )

      expect(Evaluation::SyntheticDatasetJob).to have_received(:perform_later).with(
        draft_token: draft_token,
        agent_name:  agent_name,
        dataset_name: dataset_name,
        count: 5,
        hints: ""
      )
    end

    it "clamps count to maximum of 50" do
      described_class.call(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: 200
      )

      expect(Evaluation::SyntheticDatasetJob).to have_received(:perform_later).with(
        hash_including(count: 50)
      )
    end

    it "clamps count to minimum of 1" do
      described_class.call(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: 0
      )

      expect(Evaluation::SyntheticDatasetJob).to have_received(:perform_later).with(
        hash_including(count: 1)
      )
    end

    it "returns the draft_token" do
      result = described_class.call(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: 5
      )

      expect(result).to eq(draft_token)
    end

    it "forwards optional hints" do
      described_class.call(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: 3, hints: "focus on spam"
      )

      expect(Evaluation::SyntheticDatasetJob).to have_received(:perform_later).with(
        hash_including(hints: "focus on spam")
      )
    end
  end
end
