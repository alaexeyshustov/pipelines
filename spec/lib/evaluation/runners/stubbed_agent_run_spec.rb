# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Runners::StubbedAgentRun do # rubocop:disable RSpec/MultipleMemoizedHelpers
  subject(:runner) { described_class.new }

  let(:orchestration_agent) do
    create(:orchestration_agent,
           name: "Emails::ClassifyAgent",
           model: "mistral-large-latest",
           tools: [ "Records::TempFileTool" ],
           output_schema: {
             "type" => "object",
             "properties" => {
               "results" => {
                 "type" => "array",
                 "items" => {
                   "type" => "object",
                   "properties" => {
                     "id"   => { "type" => "string" },
                     "tags" => { "type" => "array", "items" => { "type" => "string" } }
                   }
                 }
               }
             }
           })
  end
  let(:step_action) do
    action = create(:orchestration_action, kind: :agent, agent: orchestration_agent)
    create(:orchestration_step_action, action: action)
  end
  let(:classify_prompt) { create(:orchestration_prompt, name: "Emails::ClassifyAgent") }
  let(:experiment) { create(:evaluation_experiment, prompt: classify_prompt) }
  let(:dataset_sample) do
    create(:evaluation_dataset_sample,
           dataset: experiment.dataset,
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] },
           expected_tool_calls: [
             { "tool_name" => "temp_file", "arguments" => { "action" => "read", "filename" => "emails.txt" }, "result" => "emails list content" }
           ])
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
    orchestration_agent
    step_action
    runner.instance_variable_set(:@experiment, experiment)
    stub_request(:post, "https://api.mistral.ai/v1/chat/completions")
      .to_return(
        { status: 200, body: mistral_tool_call_response.to_json, headers: { "Content-Type" => "application/json" } }
      ).then.to_return(
        { status: 200, body: mistral_final_response.to_json, headers: { "Content-Type" => "application/json" } }
      )
  end

  describe "#execute" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when no matching agent exists for the experiment" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "raises ArgumentError with a descriptive message" do
        runner.instance_variable_set(:@experiment, nil)
        ds = create(:evaluation_dataset_sample)
        expect { runner.execute(ds) }.to raise_error(ArgumentError, /No agent found/)
      end
    end

    it "returns a JSON string prediction" do
      result = runner.execute(dataset_sample)

      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end

    it "includes the tool calls made during the run" do
      result = runner.execute(dataset_sample)
      parsed = JSON.parse(result)

      expect(parsed["tool_calls"]).to be_an(Array)
      expect(parsed["tool_calls"].first["tool_name"]).to eq("temp_file")
    end

    it "includes the final agent output" do
      result = runner.execute(dataset_sample)
      parsed = JSON.parse(result)

      expect(parsed["output"]).to eq(JSON.parse(final_output))
    end

    it "uses stubbed tools so no real filesystem or network calls are made" do
      # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(Evaluation::ToolStubRegistry)
        .to receive(:lookup)
        .with(tool_name: "temp_file", arguments: hash_including("action" => "read", "filename" => "emails.txt"))
        .and_call_original
      # rubocop:enable RSpec/AnyInstance

      runner.execute(dataset_sample)
    end

    context "when the runner has a Leva prompt" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:evaluation_prompt) do
        create(:orchestration_prompt,
               name: "Emails::ClassifyAgent",
               system_prompt: "Custom instructions for evaluation.",
               user_prompt: "{{input}}")
      end

      before { runner.instance_variable_set(:@prompt, evaluation_prompt) }

      it "passes the prompt system_prompt as prompt_override to AgentResolutionPolicy" do
        allow(Orchestration::AgentResolutionPolicy).to receive(:call).and_call_original
        runner.execute(dataset_sample)
        expect(Orchestration::AgentResolutionPolicy).to have_received(:call)
          .with(hash_including(prompt_override: "Custom instructions for evaluation."))
      end
    end

    context "when experiment has a sample_model" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:experiment) do
        create(:evaluation_experiment,
               prompt: classify_prompt,
               runner_class: "Evaluation::Runners::StubbedAgentRun",
               sample_model: "mistral-small-latest")
      end

      before { runner.instance_variable_set(:@experiment, experiment) }

      it "passes sample_model as pipeline_model to AgentResolutionPolicy" do
        allow(Orchestration::AgentResolutionPolicy).to receive(:call).and_call_original
        runner.execute(dataset_sample)
        expect(Orchestration::AgentResolutionPolicy).to have_received(:call)
          .with(hash_including(pipeline_model: "mistral-small-latest"))
      end
    end

    context "with a serialized orchestration agent and no Ruby subclass" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:orchestration_agent) do
        create(:orchestration_agent,
               name: "Reusable email classifier",
               model: "mistral-large-latest",
               tools: [ "Records::TempFileTool" ],
               output_schema: {
                 "type" => "object",
                 "required" => [ "results" ],
                 "properties" => {
                   "results" => {
                     "type" => "array",
                     "items" => {
                       "type" => "object",
                       "required" => [ "id" ],
                       "properties" => {
                         "id" => { "type" => "string" },
                         "tags" => { "type" => "array", "items" => { "type" => "string" } }
                       }
                     }
                   }
                 }
               })
      end
      let(:classify_prompt) { create(:orchestration_prompt, name: "Reusable email classifier") }

      it "replays the configured tools and structured output through the generic runtime" do
        result = runner.execute(dataset_sample)
        parsed = JSON.parse(result)

        expect(parsed["tool_calls"].first["tool_name"]).to eq("temp_file")
        expect(parsed["output"]).to eq(JSON.parse(final_output))
      end
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
