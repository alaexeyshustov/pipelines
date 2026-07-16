# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::AgentRunsQuery do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
  let(:action) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }
  let(:step_action) { create(:orchestration_step_action, action: action) }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }

  def build_action_run(status: "completed", chat: create(:chat), step_action: self.step_action)
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: status,
           chat: chat,
           input: { "email" => "subject: Job offer" })
  end

  describe ".completed_with_chat" do
    it "returns a Run DTO for a completed action run with a chat, for the given agent" do
      action_run = build_action_run
      runs = described_class.completed_with_chat(agent_name: agent_name, limit: 10)

      expect(runs.size).to eq(1)
      expect(runs.first.id).to eq(action_run.id)
      expect(runs.first.input).to eq(action_run.input)
    end

    it "returns actual Run DTOs, not raw ActionRun records" do
      build_action_run
      runs = described_class.completed_with_chat(agent_name: agent_name, limit: 10)

      expect(runs.first).to be_a(described_class::Run)
    end

    it "exposes the live chat association object, not a serialized copy" do
      action_run = build_action_run
      runs = described_class.completed_with_chat(agent_name: agent_name, limit: 10)

      expect(runs.first.chat).to eq(action_run.chat)
      expect(runs.first.chat).to be_a(Chat)
    end

    it "excludes action runs that are not completed" do
      build_action_run(status: "failed")
      runs = described_class.completed_with_chat(agent_name: agent_name, limit: 10)

      expect(runs).to be_empty
    end

    it "excludes action runs without a chat" do
      build_action_run(chat: nil)
      runs = described_class.completed_with_chat(agent_name: agent_name, limit: 10)

      expect(runs).to be_empty
    end

    context "with an action run belonging to a different agent" do
      let(:other_agent) { create(:orchestration_agent, name: "Emails::FilterAgent") }
      let(:other_action) { create(:orchestration_action, kind: :agent, agent: other_agent) }
      let(:other_step_action) { create(:orchestration_step_action, action: other_action) }
      let(:other_pipeline_run) { create(:orchestration_pipeline_run, pipeline: other_step_action.step.pipeline) }

      before do
        create(:orchestration_action_run,
               step_action: other_step_action,
               pipeline_run: other_pipeline_run,
               status: "completed",
               chat: create(:chat),
               input: { "other" => true })
      end

      it "excludes action runs belonging to a different agent" do
        runs = described_class.completed_with_chat(agent_name: agent_name, limit: 10)

        expect(runs).to be_empty
      end
    end

    it "respects the limit" do
      3.times { build_action_run }
      runs = described_class.completed_with_chat(agent_name: agent_name, limit: 2)

      expect(runs.size).to eq(2)
    end
  end
end
