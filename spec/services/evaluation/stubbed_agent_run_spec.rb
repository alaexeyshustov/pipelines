require "rails_helper"

RSpec.describe Evaluation::StubbedAgentRun do # rubocop:disable RSpec/MultipleMemoizedHelpers
  subject(:runner) { described_class.new }

  let(:step_action) do
    action = create(:orchestration_action, agent_class: "Emails::ClassifyAgent")
    create(:orchestration_step_action, action: action)
  end
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }

  let(:historical_chat) do
    chat = create(:chat)
    msg = create(:message, chat: chat, role: "assistant", content: nil)
    tc = create(:tool_call, message: msg, name: "temp_file",
                            arguments: { "action" => "read", "filename" => "emails.txt" })
    create(:message, chat: chat, role: "tool", content: "emails list content", parent_tool_call: tc)
    chat
  end

  let(:action_run) do
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: "completed",
           chat: historical_chat,
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] })
  end

  let(:final_output) { '{"results":[{"id":"1","tags":["job"]}]}' }

  let(:mistral_tool_call_response) do
    {
      id: "chatcmpl-1", object: "chat.completion", model: "mistral-large-latest",
      choices: [ {
        index: 0,
        message: {
          role: "assistant", content: nil,
          tool_calls: [ { id: "call_abc", type: "function",
                          function: { name: "temp_file",
                                      arguments: { action: "read", filename: "emails.txt" }.to_json } } ]
        },
        finish_reason: "tool_calls"
      } ],
      usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120 }
    }
  end

  let(:mistral_final_response) do
    {
      id: "chatcmpl-2", object: "chat.completion", model: "mistral-large-latest",
      choices: [ {
        index: 0,
        message: { role: "assistant", content: final_output },
        finish_reason: "stop"
      } ],
      usage: { prompt_tokens: 150, completion_tokens: 30, total_tokens: 180 }
    }
  end

  before do
    stub_request(:post, "https://api.mistral.ai/v1/chat/completions")
      .to_return(
        { status: 200, body: mistral_tool_call_response.to_json, headers: { "Content-Type" => "application/json" } }
      ).then.to_return(
        { status: 200, body: mistral_final_response.to_json, headers: { "Content-Type" => "application/json" } }
      )
  end

  describe "#execute" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it "returns a JSON string prediction" do
      result = runner.execute(action_run)

      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end

    it "includes the tool calls made during the run" do
      result = runner.execute(action_run)
      parsed = JSON.parse(result)

      expect(parsed["tool_calls"]).to be_an(Array)
      expect(parsed["tool_calls"].first["tool_name"]).to eq("temp_file")
    end

    it "includes the final agent output" do
      result = runner.execute(action_run)
      parsed = JSON.parse(result)

      expect(JSON.parse(parsed["output"])).to eq(JSON.parse(final_output))
    end

    it "uses stubbed tools so no real filesystem or network calls are made" do
      expect { runner.execute(action_run) }.not_to raise_error
    end
  end

  describe "#stub_tool" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:empty_registry) { Evaluation::ToolStubRegistry.new([]) }

    it "produces a subclass of the original tool" do
      stub_class = runner.send(:stub_tool, Records::TempFileTool, empty_registry)

      expect(stub_class.superclass).to eq(Records::TempFileTool)
    end

    it "preserves the tool name" do
      stub_class = runner.send(:stub_tool, Records::TempFileTool, empty_registry)

      expect(stub_class.new.name).to eq(Records::TempFileTool.new.name)
    end

    it "overrides execute to look up in the registry" do
      allow(Rails.logger).to receive(:warn)
      registry = Evaluation::ToolStubRegistry.new(
        [ { tool_name: "temp_file", arguments: { "action" => "read", "filename" => "f.txt" }, result: "data" } ]
      )
      stub_class = runner.send(:stub_tool, Records::TempFileTool, registry)

      expect(stub_class.new.execute(action: "read", filename: "f.txt")).to eq("data")
    end
  end
end
