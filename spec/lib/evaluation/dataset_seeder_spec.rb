# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::DatasetSeeder do
  let(:agent_name) { "Emails::ClassifyAgent" }

  let(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
  let(:action) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }
  let(:step_action) { create(:orchestration_step_action, action: action) }

  def completed_action_run(chat: nil)
    chat ||= create(:chat)
    create(:orchestration_action_run, step_action: step_action, status: "completed", chat: chat)
  end

  describe ".call" do
    it "creates a Dataset when one does not exist" do
      expect { described_class.call(agent_name: agent_name) }
        .to change(Evaluation::Dataset, :count).by(1)
    end

    it "reuses an existing Dataset with the same name" do
      Evaluation::Dataset.create!(name: agent_name)
      expect { described_class.call(agent_name: agent_name) }
        .not_to change(Evaluation::Dataset, :count)
    end

    it "creates DatasetRecords for completed ActionRuns belonging to the agent" do
      completed_action_run
      expect { described_class.call(agent_name: agent_name) }
        .to change(Evaluation::DatasetRecord, :count).by(1)
    end

    it "does not create DatasetRecords for ActionRuns with a different agent" do
      other_agent = create(:orchestration_agent, name: "Other::Agent")
      other_action = create(:orchestration_action, kind: :agent, agent: other_agent)
      other_step = create(:orchestration_step_action, action: other_action)
      create(:orchestration_action_run, step_action: other_step, status: "completed", chat: create(:chat))

      expect { described_class.call(agent_name: agent_name) }
        .not_to change(Evaluation::DatasetRecord, :count)
    end

    it "skips ActionRuns with no associated chat" do
      create(:orchestration_action_run, step_action: step_action, status: "completed", chat: nil)
      expect { described_class.call(agent_name: agent_name) }
        .not_to change(Evaluation::DatasetRecord, :count)
    end

    it "returns a Result with the correct created count" do
      completed_action_run
      result = described_class.call(agent_name: agent_name)
      expect(result.created).to eq(1)
      expect(result.skipped).to eq(0)
    end

    it "returns a Result with the correct skipped count for existing records" do
      run = completed_action_run
      Evaluation::Dataset.create!(name: agent_name).tap do |ds|
        ds.dataset_records.create!(recordable: run)
      end
      result = described_class.call(agent_name: agent_name)
      expect(result.created).to eq(0)
      expect(result.skipped).to eq(1)
    end

    it "respects the sample_size limit" do
      3.times { completed_action_run }
      result = described_class.call(agent_name: agent_name, sample_size: 2)
      expect(result.created).to eq(2)
    end
  end
end
