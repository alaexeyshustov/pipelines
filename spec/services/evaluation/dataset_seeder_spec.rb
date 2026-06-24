# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::DatasetSeeder do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
  let(:action) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }
  let(:step_action) { create(:orchestration_step_action, action: action) }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }
  let(:chat) { create(:chat) }

  def build_action_run(status: "completed", chat: self.chat, step_action: self.step_action)
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: status,
           chat: chat,
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] })
  end

  describe ".call" do
    it "creates a dataset named after the agent" do
      build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)
      expect(Evaluation::Dataset.find_by(name: agent_name)).to be_present
    end

    it "creates a dataset sample linking the action run via source_run_id" do
      action_run = build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.first.source_run_id).to eq(action_run.id)
    end

    it "copies input from the action run's input field" do
      action_run = build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)

      sample = Evaluation::Dataset.find_by!(name: agent_name).dataset_samples.first
      expect(sample.input).to eq(action_run.input)
    end

    it "stores expected_tool_calls extracted via ToolCallExtractor" do
      tool_calls = [ { "tool_name" => "search", "arguments" => { "q" => "jobs" }, "result" => "ok" } ]
      allow(Evaluation::ToolCallExtractor).to receive(:call).and_return(tool_calls)

      build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)

      sample = Evaluation::Dataset.find_by!(name: agent_name).dataset_samples.first
      expect(sample.expected_tool_calls).to eq(tool_calls)
    end

    it "skips action runs with status other than completed" do
      build_action_run(status: "failed")
      described_class.call(agent_name: agent_name, sample_size: 10)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(0)
    end

    it "skips action runs without a chat" do
      build_action_run(chat: nil)
      described_class.call(agent_name: agent_name, sample_size: 10)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(0)
    end

    it "skips action runs with service-kind step actions" do # rubocop:disable RSpec/ExampleLength
      service_action = create(:orchestration_action, kind: :service, agent: nil, agent_class: "Orchestration::Executors::Query")
      service_step_action = create(:orchestration_step_action, action: service_action)
      service_pipeline_run = create(:orchestration_pipeline_run, pipeline: service_step_action.step.pipeline)
      create(:orchestration_action_run,
             step_action: service_step_action,
             pipeline_run: service_pipeline_run,
             status: "completed",
             chat: chat)

      described_class.call(agent_name: agent_name, sample_size: 10)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(0)
    end

    it "skips action runs for a different agent name" do # rubocop:disable RSpec/ExampleLength
      other_agent = create(:orchestration_agent, name: "Emails::FilterAgent")
      other_action = create(:orchestration_action, kind: :agent, agent: other_agent)
      other_step_action = create(:orchestration_step_action, action: other_action)
      create(:orchestration_action_run,
             step_action: other_step_action,
             pipeline_run: create(:orchestration_pipeline_run, pipeline: other_step_action.step.pipeline),
             status: "completed",
             chat: chat)

      described_class.call(agent_name: agent_name, sample_size: 10)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(0)
    end

    it "respects sample_size limit" do
      3.times { build_action_run(chat: create(:chat)) }

      described_class.call(agent_name: agent_name, sample_size: 2)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(2)
    end

    it "does not duplicate dataset samples when called twice" do
      build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)
      described_class.call(agent_name: agent_name, sample_size: 10)

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(1)
    end

    it "does not duplicate the dataset when called twice" do
      build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)
      described_class.call(agent_name: agent_name, sample_size: 10)

      expect(Evaluation::Dataset.where(name: agent_name).count).to eq(1)
    end

    it "returns a result with agent_name, created, and skipped counts" do
      build_action_run
      result = described_class.call(agent_name: agent_name, sample_size: 10)

      expect(result.agent_name).to eq(agent_name)
      expect(result.created).to eq(1)
      expect(result.skipped).to eq(0)
    end

    it "returns correct skipped count on second call" do
      build_action_run
      described_class.call(agent_name: agent_name, sample_size: 10)
      result = described_class.call(agent_name: agent_name, sample_size: 10)

      expect(result.created).to eq(0)
      expect(result.skipped).to eq(1)
    end
  end
end
