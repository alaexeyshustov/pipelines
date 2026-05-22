# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Sampler do # rubocop:disable RSpec/MultipleMemoizedHelpers
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
                                      arguments: { action: "write", filename: "output.txt", content: "data" }.to_json } } ]
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
    stub_request(:post, "https://api.mistral.ai/v1/chat/completions")
      .to_return(
        { status: 200, body: mistral_tool_call_response.to_json, headers: { "Content-Type" => "application/json" } }
      ).then.to_return(
        { status: 200, body: mistral_final_response.to_json, headers: { "Content-Type" => "application/json" } }
      )
  end

  describe ".call" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    subject(:sample) do
      described_class.call(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
    end

    it "creates and returns a Sample record" do
      expect { sample }.to change(Evaluation::Sample, :count).by(1)
    end

    it "returns the persisted Sample" do
      expect(sample).to be_a(Evaluation::Sample)
    end

    it "links the sample to the experiment and dataset_sample" do
      expect(sample.experiment).to eq(experiment)
      expect(sample.dataset_sample).to eq(dataset_sample)
    end

    it "captures the tool call trace" do
      expect(sample.tool_calls).to be_an(Array)
      expect(sample.tool_calls.first).to include("tool_name" => "temp_file")
    end

    it "blocks write tools and records the sentinel result in the trace" do
      expect(sample.tool_calls.first["result"]).to eq("[write tool blocked during sampling]")
    end

    it "captures the final agent output" do
      expect(sample.output).to eq(final_output)
    end

    it "logs blocked write tool calls" do
      allow(Rails.logger).to receive(:info)
      sample
      expect(Rails.logger).to have_received(:info).with(include("temp_file").and(include("blocked")))
    end

    context "when experiment has a sample_model" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:experiment) do
        create(:evaluation_experiment,
               prompt: classify_prompt,
               sample_model: "mistral-small-latest")
      end

      it "passes sample_model to AgentResolutionPolicy" do
        allow(Orchestration::AgentResolutionPolicy).to receive(:call).and_call_original
        sample
        expect(Orchestration::AgentResolutionPolicy).to have_received(:call)
          .with(hash_including(pipeline_model: "mistral-small-latest"))
      end
    end

    context "when a prompt with a system_prompt override is given" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:evaluation_prompt) do
        create(:orchestration_prompt,
               name: "Emails::ClassifyAgent",
               system_prompt: "Custom evaluation instructions.")
      end

      it "passes the system_prompt as prompt_override to AgentResolutionPolicy" do
        allow(Orchestration::AgentResolutionPolicy).to receive(:call).and_call_original
        described_class.call(experiment: experiment, dataset_sample: dataset_sample, prompt: evaluation_prompt)
        expect(Orchestration::AgentResolutionPolicy).to have_received(:call)
          .with(hash_including(prompt_override: "Custom evaluation instructions."))
      end
    end

    context "when the agent tool is read-only" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:orchestration_agent) do
        create(:orchestration_agent,
               name: "Emails::ClassifyAgent",
               model: "mistral-large-latest",
               tools: [ "Records::ReadRowsTool" ])
      end

      let(:mistral_tool_call_response) do
        {
          id: "chatcmpl-1", object: "chat.completion", model: "mistral-large-latest",
          choices: [ {
            index: 0,
            message: {
              role: "assistant", content: nil,
              tool_calls: [ { id: "call_abc", type: "function",
                              function: { name: "read_rows",
                                          arguments: { table: "emails", filters: {} }.to_json } } ]
            },
            finish_reason: "tool_calls"
          } ],
          usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120 }
        }
      end

      it "does not return the sentinel for read-only tools" do
        expect(sample.tool_calls.first["result"]).not_to eq("[write tool blocked during sampling]")
      end
    end

    context "when the agent returns output without calling any tools" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:mistral_no_tool_response) do
        {
          id: "chatcmpl-1", object: "chat.completion", model: "mistral-large-latest",
          choices: [ {
            index: 0,
            message: { role: "assistant", content: final_output },
            finish_reason: "stop"
          } ],
          usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 }
        }
      end

      before do
        stub_request(:post, "https://api.mistral.ai/v1/chat/completions")
          .to_return(
            status: 200,
            body: mistral_no_tool_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "creates the sample with an empty tool_calls array" do
        expect(sample.tool_calls).to eq([])
      end

      it "captures the final output" do
        expect(sample.output).to eq(final_output)
      end
    end

    context "when no agent is found for the experiment" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "raises ArgumentError" do
        other_experiment = create(:evaluation_experiment)
        other_sample = create(:evaluation_dataset_sample, dataset: other_experiment.dataset)

        expect {
          described_class.call(experiment: other_experiment, dataset_sample: other_sample, prompt: other_experiment.prompt)
        }.to raise_error(ArgumentError, /No agent found/)
      end
    end
  end
end
