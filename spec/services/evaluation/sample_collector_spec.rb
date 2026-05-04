require "rails_helper"

RSpec.describe Evaluation::SampleCollector do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
  let(:action) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }
  let(:step_action) { create(:orchestration_step_action, action: action) }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }
  let(:chat) { create(:chat) }

  def build_action_run(status: "completed", chat: self.chat)
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: status,
           chat: chat,
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] })
  end

  def add_tool_call(chat, name: "temp_file", arguments: { "action" => "read", "filename" => "out.txt" }, result: "file contents")
    msg = create(:message, chat: chat, role: "assistant", content: nil)
    tc = create(:tool_call, message: msg, name: name, arguments: arguments)
    create(:message, chat: chat, role: "tool", content: result, parent_tool_call: tc)
  end

  describe ".call" do
    it "returns samples from completed action runs with chat histories" do
      add_tool_call(chat)
      build_action_run

      samples = described_class.call(agent_name: agent_name, sample_size: 10)

      expect(samples).not_to be_empty
      expect(samples.first).to be_a(Evaluation::SampleCollector::Sample)
    end

    it "filters out action runs without chat_id" do
      build_action_run(chat: nil)

      expect(described_class.call(agent_name: agent_name, sample_size: 10)).to be_empty
    end

    it "filters out non-completed action runs" do
      build_action_run(status: "failed")

      expect(described_class.call(agent_name: agent_name, sample_size: 10)).to be_empty
    end

    it "respects sample_size limit" do
      3.times { build_action_run(chat: create(:chat)) }

      expect(described_class.call(agent_name: agent_name, sample_size: 2).size).to eq(2)
    end

    it "only returns samples for the given agent_name" do # rubocop:disable RSpec/ExampleLength
      other_agent = create(:orchestration_agent, name: "Emails::FilterAgent")
      other_sa = create(:orchestration_step_action,
                        action: create(:orchestration_action, kind: :agent, agent: other_agent))
      create(:orchestration_action_run,
             step_action: other_sa,
             pipeline_run: create(:orchestration_pipeline_run, pipeline: other_sa.step.pipeline),
             status: "completed", chat: create(:chat), input: {})
      own_run = build_action_run

      samples = described_class.call(agent_name: agent_name, sample_size: 10)

      expect(samples.map(&:action_run_id)).to all(eq(own_run.id))
    end
  end

  describe "Sample" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let!(:action_run) { build_action_run }
    let(:sample) { described_class.call(agent_name: agent_name, sample_size: 10).find { |s| s.action_run_id == action_run.id } }

    before { add_tool_call(chat) }


    it "has action_run_id, input, and expected_tool_calls" do
      expect(sample.action_run_id).to eq(action_run.id)
      expect(sample.input).to eq(action_run.input)
      expect(sample.expected_tool_calls).to be_an(Array)
    end

    it "extracts tool call sequences from chat messages" do
      add_tool_call(chat, name: "temp_file",
                    arguments: { "action" => "write", "filename" => "out2.txt" },
                    result: "hello world")

      calls = described_class.call(agent_name: agent_name, sample_size: 10)
                             .find { |s| s.action_run_id == action_run.id }
                             .expected_tool_calls

      expect(calls).to include(hash_including(tool_name: "temp_file", result: "hello world"))
    end

    it "extracts multiple tool calls in order" do
      msg2 = create(:message, chat: chat, role: "assistant", content: nil)
      tc2 = create(:tool_call, message: msg2, name: "temp_file",
                               arguments: { "action" => "write", "filename" => "b.txt" })
      create(:message, chat: chat, role: "tool", content: "second result", parent_tool_call: tc2)

      calls = described_class.call(agent_name: agent_name, sample_size: 10)
                             .find { |s| s.action_run_id == action_run.id }
                             .expected_tool_calls

      expect(calls.size).to be >= 2
      expect(calls.last[:result]).to eq("second result")
    end

    it "returns empty expected_tool_calls when chat has no tool calls" do
      no_tool_chat = create(:chat)
      create(:message, chat: no_tool_chat, role: "user", content: "classify")
      create(:message, chat: no_tool_chat, role: "assistant", content: '{"results":[]}')
      empty_run = build_action_run(chat: no_tool_chat)

      empty_sample = described_class.call(agent_name: agent_name, sample_size: 10)
                                    .find { |s| s.action_run_id == empty_run.id }

      expect(empty_sample.expected_tool_calls).to be_empty
    end
  end
end
