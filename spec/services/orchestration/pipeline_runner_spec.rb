require 'rails_helper'

RSpec.describe Orchestration::PipelineRunner do
  let(:pipeline)     { create(:orchestration_pipeline) }
  let(:step1)        { create(:orchestration_step, pipeline: pipeline, name: "extract", position: 1) }
  let(:action)       { create(:orchestration_action, agent: create(:orchestration_agent, name: "Emails::ClassifyAgent")) }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: pipeline, status: "pending") }
  let(:stub_agent)   { instance_double(RubyLLM::Agent) }

  before do
    allow(RubyLLM::Agent).to receive(:new).and_return(stub_agent)
    allow(stub_agent).to receive_messages(ask: instance_double(RubyLLM::Message, content: "classification result"), chat: instance_double(Chat, id: nil))
  end

  describe '#call' do
    context 'with a single step and one action' do
      before { create(:orchestration_step_action, step: step1, action: action, position: 1) }

      it 'transitions PipelineRun from pending to completed' do
        expect { described_class.new(pipeline_run).call }
          .to change { pipeline_run.reload.status }.from("pending").to("completed")
      end

      it 'creates an ActionRun for the step action' do
        expect { described_class.new(pipeline_run).call }
          .to change(Orchestration::ActionRun, :count).by(1)
      end

      it 'marks the ActionRun completed with output from the agent' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "result" => "classification result" })
      end

      it 'stores the chat_id on the ActionRun after building the agent' do
        chat = create(:chat)
        allow(stub_agent).to receive(:chat).and_return(chat)
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.chat_id).to eq(chat.id)
      end
    end

    context 'when the pipeline has a model set' do
      before do
        pipeline.update!(model: 'mistral-large-latest')
        action.agent.update!(model: 'openai-gpt4')
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:with_model).and_return(stub_agent)
      end

      it 'applies the pipeline model, overriding the action model' do
        described_class.new(pipeline_run).call
        expect(stub_agent).to have_received(:with_model).with('mistral-large-latest')
      end
    end

    context 'when the pipeline has no model but the action does' do
      before do
        pipeline.update!(model: nil)
        action.agent.update!(model: 'openai-gpt4')
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:with_model).and_return(stub_agent)
      end

      it 'falls back to the action model' do
        described_class.new(pipeline_run).call
        expect(stub_agent).to have_received(:with_model).with('openai-gpt4')
      end
    end

    context 'when both pipeline and action have no model' do
      before do
        pipeline.update!(model: nil)
        action.agent.update!(model: nil)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:with_model)
      end

      it 'does not call with_model on the agent' do
        described_class.new(pipeline_run).call
        expect(stub_agent).not_to have_received(:with_model)
      end
    end

    context 'with a serialized orchestration agent configuration' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:serialized_chat) { create(:chat) }
      let(:serialized_agent) do
        instance_double(RubyLLM::Agent, chat: serialized_chat, params: {})
      end

      before do
        action.agent.update!(
          name: "Reusable email classifier",
          model: "mistral-small",
          tools: [ "Records::TempFileTool" ],
          prompt: "Classify incoming emails",
          params: { "mode" => "default", "limit" => 1 },
          output_schema: {
            "type" => "object",
            "required" => [ "result" ],
            "properties" => {
              "result" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "required" => [ "id" ],
                  "properties" => {
                    "id" => { "type" => "string" }
                  }
                }
              }
            }
          }
        )
        create(:orchestration_step_action, step: step1, action: action, position: 1, params: { "limit" => 2 })
        allow(RubyLLM::Agent).to receive(:new).and_return(serialized_agent)
        allow(serialized_chat).to receive(:with_instructions)
        allow(serialized_agent).to receive_messages(with_model: serialized_agent, with_tools: serialized_agent, with_schema: serialized_agent, ask: instance_double(RubyLLM::Message, content: { "result" => [ { "id" => "mail-1" } ] }))
      end

      it 'executes without relying on a Ruby agent subclass' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last

        expect(RubyLLM::Agent).to have_received(:new)
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "result" => [ { "id" => "mail-1" } ] })
      end

      it 'passes merged agent-default and step params into the ask call' do
        described_class.new(pipeline_run).call

        expect(serialized_agent).to have_received(:ask)
          .with(satisfy { |json| JSON.parse(json) == { "mode" => "default", "limit" => 2 } })
      end

      it 'uses the database output schema for structured output requests' do # rubocop:disable RSpec/ExampleLength
        described_class.new(pipeline_run).call

        expect(serialized_agent).to have_received(:with_schema).with(
          "type" => "object",
          "required" => [ "result" ],
          "properties" => {
            "result" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "required" => [ "id" ],
                "properties" => {
                  "id" => { "type" => "string" }
                }
              }
            }
          }
        )
      end
    end

    context 'with agent snapshot persistence' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:agent_record) do
        action.agent.tap do |a|
          a.update!(
            name: "Reusable email classifier",
            model: "mistral-small",
            tools: [ "Records::TempFileTool" ],
            prompt: "Classify incoming emails",
            params: { "mode" => "default" }
          )
        end
      end
      let(:snapshot_agent) { instance_double(RubyLLM::Agent, chat: create(:chat), params: {}) }

      before do
        agent_record
        create(:orchestration_step_action, step: step1, action: action, position: 1, params: { "limit" => 2 })
        allow(RubyLLM::Agent).to receive(:new).and_return(snapshot_agent)
        allow(snapshot_agent).to receive_messages(
          with_model: snapshot_agent, with_tools: snapshot_agent,
          with_schema: snapshot_agent,
          ask: instance_double(RubyLLM::Message, content: "result")
        )
        allow(snapshot_agent.chat).to receive(:with_instructions)
      end

      it 'persists a resolved agent_snapshot on the action_run' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last

        expect(action_run.agent_snapshot).to include(
          "model" => "mistral-small",
          "prompt" => "Classify incoming emails",
          "tools" => [ "Records::TempFileTool" ],
          "params" => { "mode" => "default", "limit" => 2 }
        )
      end

      it 'does not mutate historical snapshots when the agent is later edited' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        original_snapshot = action_run.agent_snapshot.dup

        agent_record.update!(model: "mistral-large", prompt: "Updated prompt")
        action_run.reload

        expect(action_run.agent_snapshot).to eq(original_snapshot)
      end
    end

    context 'when an Evaluation::Prompt exists for the agent class' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        Evaluation::Prompt.create!(
          name: "Emails::ClassifyAgent",
          system_prompt: "Custom Leva prompt for classifier",
          user_prompt: "{{input}}"
        )
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'applies the Evaluation::Prompt system_prompt as instructions' do
        described_class.new(pipeline_run).call
        expect(chat).to have_received(:with_instructions).with("Custom Leva prompt for classifier")
      end
    end

    context 'when an Evaluation::Prompt exists for the agent' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        Evaluation::Prompt.create!(
          name: "Emails::ClassifyAgent",
          system_prompt: "Leva wins over agent prompt",
          user_prompt: "{{input}}"
        )
        action.agent.update!(prompt: "Agent-level prompt")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'prefers the Evaluation::Prompt over the agent prompt' do
        described_class.new(pipeline_run).call
        expect(chat).to have_received(:with_instructions).with("Leva wins over agent prompt")
      end
    end

    context 'when no Evaluation::Prompt exists but the agent has a prompt' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        action.agent.update!(prompt: "Agent-level fallback prompt")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'falls back to the agent prompt' do
        described_class.new(pipeline_run).call
        expect(chat).to have_received(:with_instructions).with("Agent-level fallback prompt")
      end
    end

    context 'when no Evaluation::Prompt and no agent prompt' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        action.agent.update!(prompt: nil)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'does not call with_instructions on the chat' do
        described_class.new(pipeline_run).call
        expect(chat).not_to have_received(:with_instructions)
      end
    end

    context 'with an executable action' do
      before do
        executable_action = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        create(:orchestration_step_action, step: step1, action: executable_action, position: 1)
      end

      it 'calls the executable and stores its Hash output' do
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "emails" => [] })
      end

      it 'does not persist an agent_snapshot for service-backed runs' do
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.agent_snapshot).to be_nil
      end
    end

    context 'with an executable action that has params' do
      before do
        ops = { "operations" => [ { "type" => "pick", "keys" => [ "emails" ] } ] }
        ingest_action = create(:orchestration_action, :service_kind,
                                agent_class: "Orchestration::IngestionExecutor",
                                params: ops)
        create(:orchestration_step_action, step: step1, action: ingest_action, position: 1)
        allow(Orchestration::IngestionExecutor).to receive(:call).and_return({ "emails" => [] })
      end

      it 'forwards merged params to the executable' do
        described_class.new(pipeline_run).call
        expect(Orchestration::IngestionExecutor).to have_received(:call)
          .with(anything, { "operations" => [ { "type" => "pick", "keys" => [ "emails" ] } ] })
      end
    end

    context 'when an action raises' do
      before do
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:ask).and_raise(RuntimeError, "agent exploded")
      end

      it 'marks the PipelineRun as failed with the error message' do
        described_class.new(pipeline_run).call
        pipeline_run.reload
        expect(pipeline_run.status).to eq("failed")
        expect(pipeline_run.error).to eq("agent exploded")
        expect(pipeline_run.finished_at).not_to be_nil
      end

      it 'marks the ActionRun as failed with the error message' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to eq("agent exploded")
        expect(action_run.error_details).to be_nil
      end
    end

    context "when the provider returns a low-signal HTTP error" do
      let(:response) do
        instance_double(
          Faraday::Response,
          status: 429,
          body: {
            "error" => {
              "message" => "Rate limit exceeded",
              "type" => "rate_limit"
            }
          }.to_json
        )
      end

      before do
        action.agent.update!(model: "gpt-4.1-mini")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(Rails.logger).to receive(:error)
        allow(stub_agent).to receive(:with_model).and_return(stub_agent)
        allow(stub_agent).to receive(:ask).and_raise(RubyLLM::Error.new(response, "An unknown error occurred"))
      end

      it "persists structured provider diagnostics and logs them" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
        described_class.new(pipeline_run).call

        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to eq("openai API error (429): Rate limit exceeded")
        expect(action_run.error_details).to include(
          "category" => "provider_http_error",
          "provider" => "openai",
          "model" => "gpt-4.1-mini",
          "status_code" => 429,
          "message" => "Rate limit exceeded"
        )
        expect(pipeline_run.reload.error).to eq("openai API error (429): Rate limit exceeded")
        expect(Rails.logger).to have_received(:error).with(include('"category":"provider_http_error"'))
      end
    end

    context "when the provider call hits a transport timeout" do
      before do
        action.agent.update!(model: "mistral-small-latest")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:with_model).and_return(stub_agent)
        allow(stub_agent).to receive(:ask).and_raise(Faraday::TimeoutError.new("execution expired"))
      end

      it "persists transport diagnostics" do
        described_class.new(pipeline_run).call

        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to eq("mistral transport error: execution expired")
        expect(action_run.error_details).to include(
          "category" => "transport_error",
          "provider" => "mistral",
          "model" => "mistral-small-latest",
          "message" => "execution expired"
        )
      end
    end

    context 'when a step is disabled' do
      before do
        step1.update!(enabled: false)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'skips the disabled step and completes the pipeline' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("completed")
      end

      it 'creates no ActionRuns for the disabled step' do
        expect { described_class.new(pipeline_run).call }
          .not_to change(Orchestration::ActionRun, :count)
      end
    end

    context 'when a disabled step sits between two enabled steps' do
      before do
        step_disabled = create(:orchestration_step, pipeline: pipeline, name: "disabled", position: 2, enabled: false)
        step3         = create(:orchestration_step, pipeline: pipeline, name: "load", position: 3)
        action3       = create(:orchestration_action, agent: action.agent)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        create(:orchestration_step_action, step: step_disabled, action: action, position: 1)
        create(:orchestration_step_action, step: step3, action: action3, position: 1)
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: "result"))
      end

      it 'completes the pipeline running only the enabled steps' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("completed")
        expect(Orchestration::ActionRun.count).to eq(2)
      end
    end

    context 'when step 1 fails, step 2 is not started' do
      before do
        step2   = create(:orchestration_step, pipeline: pipeline, name: "transform", position: 2)
        action2 = create(:orchestration_action, agent: action.agent)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        create(:orchestration_step_action, step: step2, action: action2, position: 1)
        allow(stub_agent).to receive(:ask).and_raise(RuntimeError, "step1 exploded")
      end

      it 'stops after step 1 and never creates an ActionRun for step 2' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("failed")
        expect(Orchestration::ActionRun.count).to eq(1)
      end
    end

    context 'when the agent has an output_schema and the output is a non-JSON string' do
      before do
        action.agent.update!(output_schema: { "type" => "object", "required" => [ "result" ],
                                              "properties" => { "result" => { "type" => "array" } } })
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        # agent returns a natural-language string — not parseable as a JSON array
        allow(stub_agent).to receive_messages(with_schema: stub_agent, ask: instance_double(RubyLLM::Message, content: "I need more information."))
      end

      it 'marks the ActionRun as failed with invalid model output diagnostics' do # rubocop:disable RSpec/MultipleExpectations
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to match(/Invalid model output/)
        expect(action_run.error_details).to include(
          "category" => "invalid_model_output",
          "message" => a_string_matching(/Invalid model output/)
        )
        expect(action_run.error_details["raw_response_excerpt"]).to include("I need more information.")
      end

      it 'marks the PipelineRun as failed' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("failed")
      end
    end

    context 'when the agent has an output_schema and the output is invalid' do
      before do
        action.agent.update!(name: "Reusable email classifier",
                             output_schema: { "type" => "object", "required" => [ "result" ],
                                              "properties" => { "result" => { "type" => "array" } } })
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        generic_agent = instance_double(RubyLLM::Agent, chat: create(:chat), params: {})
        allow(RubyLLM::Agent).to receive(:new).and_return(generic_agent)
        allow(generic_agent).to receive_messages(with_schema: generic_agent, ask: instance_double(RubyLLM::Message, content: { "result" => "not an array" }))
      end

      it 'marks the ActionRun as failed with a schema error from the agent record' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last

        expect(action_run.status).to eq("failed")
        expect(action_run.error).to match(/must be an array/)
        expect(action_run.error_details).to include("category" => "invalid_model_output")
      end
    end

    context 'when the agent has an output_schema and the output is valid JSON' do
      before do
        action.agent.update!(output_schema: { "type" => "object", "required" => [ "result" ],
                                              "properties" => { "result" => { "type" => "array" } } })
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive_messages(
          with_schema: stub_agent,
          ask: instance_double(RubyLLM::Message, content: { "result" => [ { "id" => 1 } ] })
        )
      end

      it 'marks the ActionRun as completed with the parsed JSON result' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "result" => [ { "id" => 1 } ] })
      end
    end

    context 'when the agent returns a Hash as content (already parsed)' do
      before do
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: { "key" => "value" }))
      end

      it 'passes the Hash through without raising TypeError' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "result" => { "key" => "value" } })
      end
    end

    context 'with two steps' do
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "transform", position: 2)
        action2 = create(:orchestration_action, agent: action.agent)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        create(:orchestration_step_action, step: step2, action: action2, position: 1)
        allow(stub_agent).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: "step output"))
      end

      it 'completes both steps and the PipelineRun' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("completed")
        expect(Orchestration::ActionRun.where(status: "completed").count).to eq(2)
      end

      it 'gives step2 an empty input when it has no input_mapping' do
        described_class.new(pipeline_run).call
        step2_action_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .where(steps: { name: "transform" }).first
        expect(step2_action_run.input).to eq({})
      end
    end

    context 'when pipeline_run has initial_input' do
      before do
        pipeline_run.update!(initial_input: { "date" => "2026-04-03", "providers" => [ "gmail" ] })
        executable_action = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        create(:orchestration_step_action, step: step1, action: executable_action, position: 1)
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
      end

      it 'gives step 1 empty input when it has no input_mapping (initial_input is not auto-merged)' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.input).to eq({})
      end
    end

    context 'when pipeline_run has an empty initial_input and a step maps from _initial' do
      before do
        pipeline_run.update!(initial_input: {})
        executable_action = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        create(:orchestration_step_action,
               step: step1, action: executable_action, position: 1,
               input_mapping: { "data" => { "from" => "_initial" } })
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
      end

      it 'seeds _initial even for an empty hash so explicit mappings resolve without UnknownOutputKey' do
        described_class.new(pipeline_run).call
        expect(Emails::FetchExecutor).to have_received(:call).with({ "data" => {} }, anything)
        expect(pipeline_run.reload.status).to eq("completed")
      end
    end

    context 'with three steps where step 3 needs step 1 output (accumulation)' do
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "filter",  position: 2)
        step3 = create(:orchestration_step, pipeline: pipeline, name: "ingest",  position: 3)

        filter_agent_record = create(:orchestration_agent, name: "Emails::FilterAgent")

        fetch_action  = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        filter_action = create(:orchestration_action, agent: filter_agent_record)
        ingest_action = create(:orchestration_action, :service_kind,
                                agent_class: "Orchestration::IngestionExecutor",
                                params: {
                                  "operations" => [
                                    { "type" => "filter_by_ids", "source" => "emails",
                                      "ids_from" => "result.results", "output" => "emails" },
                                    { "type" => "pick", "keys" => [ "emails" ] }
                                  ]
                                })

        create(:orchestration_step_action, step: step1, action: fetch_action,  position: 1)
        create(:orchestration_step_action, step: step2, action: filter_action, position: 1)
        create(:orchestration_step_action, step: step3, action: ingest_action, position: 1)

        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [ { "id" => "e1" } ] })
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: { "results" => [ { "id" => "e1" } ] }))
      end

      it 'gives step 3 empty input when it has no input_mapping (cross-step data requires explicit mapping)' do
        described_class.new(pipeline_run).call

        ingest_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .find_by(steps: { name: "ingest" })

        expect(ingest_run.input).to eq({})
      end
    end

    context 'when output_schema is on the agent record (fix for Run #66)' do
      let(:store_schema) do
        { "type" => "object", "required" => [ "result" ], "properties" => { "result" => { "type" => "object" } } }
      end

      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent", output_schema: store_schema)
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive_messages(
          with_schema: stub_agent,
          ask: instance_double(RubyLLM::Message, content: { "result" => { "rows_inserted" => 1, "ids" => [ 42 ] } })
        )
      end

      it 'calls with_schema, skips wrapping, and stores output as-is' do
        described_class.new(pipeline_run).call

        store_run = Orchestration::ActionRun.last
        expect(store_run.status).to eq("completed")
        expect(store_run.output).to eq({ "result" => { "rows_inserted" => 1, "ids" => [ 42 ] } })
        expect(stub_agent).to have_received(:with_schema).with(store_schema)
      end
    end

    context 'when schema is missing additionalProperties: false (regression: Run #67)' do
      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent",
                                    output_schema: {
                                      "type" => "object", "required" => [ "result" ],
                                      "properties" => { "result" => { "type" => "object" } }
                                    })
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive(:with_schema).and_return(stub_agent)
        allow(stub_agent).to receive(:ask)
          .and_raise(RuntimeError, "Invalid schema for response_format 'response': " \
                                   "In context=(), 'additionalProperties' is required to be supplied and to be false.")
      end

      it 'marks the action_run as failed with the Mistral schema error' do
        described_class.new(pipeline_run).call

        store_run = Orchestration::ActionRun.last
        expect(store_run.status).to eq("failed")
        expect(store_run.error).to match(/additionalProperties/)
      end
    end

    context 'when schema includes additionalProperties: false at all object levels (fix for Run #67)' do
      let(:store_schema) do
        {
          "type"                 => "object",
          "additionalProperties" => false,
          "required"             => [ "result" ],
          "properties"           => {
            "result" => {
              "type"                 => "object",
              "additionalProperties" => false,
              "properties"           => {
                "rows_inserted" => { "type" => "integer" },
                "ids"           => { "type" => "array" }
              }
            }
          }
        }
      end

      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent", output_schema: store_schema)
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive_messages(
          with_schema: stub_agent,
          ask: instance_double(RubyLLM::Message, content: { "result" => { "rows_inserted" => 1, "ids" => [ 42 ] } })
        )
      end

      it 'calls with_schema with additionalProperties: false at all levels and completes successfully' do
        described_class.new(pipeline_run).call

        expect(stub_agent).to have_received(:with_schema).with(
          hash_including(
            "additionalProperties" => false,
            "properties"           => hash_including(
              "result" => hash_including("additionalProperties" => false)
            )
          )
        )
        expect(Orchestration::ActionRun.last.status).to eq("completed")
      end
    end

    context 'when schema has array field missing items (regression: Run #68)' do
      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent",
                                    output_schema: {
                                      "type" => "object", "additionalProperties" => false,
                                      "required" => [ "result" ],
                                      "properties" => {
                                        "result" => {
                                          "type" => "object", "additionalProperties" => false,
                                          "properties" => {
                                            "rows_inserted" => { "type" => "integer" },
                                            "ids"           => { "type" => "array" }
                                          }
                                        }
                                      }
                                    })
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive(:with_schema).and_return(stub_agent)
        allow(stub_agent).to receive(:ask)
          .and_raise(RuntimeError, "Invalid schema for response_format 'response': " \
                                   "In context=('properties', 'result', 'properties', 'ids'), array schema missing items.")
      end

      it 'marks the action_run as failed with the Mistral schema error' do
        described_class.new(pipeline_run).call

        store_run = Orchestration::ActionRun.last
        expect(store_run.status).to eq("failed")
        expect(store_run.error).to match(/array schema missing items/)
      end
    end

    context 'when schema includes items on all array fields (fix for Run #68)' do
      let(:store_schema) do
        {
          "type"                 => "object",
          "additionalProperties" => false,
          "required"             => [ "result" ],
          "properties"           => {
            "result" => {
              "type"                 => "object",
              "additionalProperties" => false,
              "properties"           => {
                "rows_inserted" => { "type" => "integer" },
                "ids"           => { "type" => "array", "items" => {} }
              }
            }
          }
        }
      end

      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent", output_schema: store_schema)
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive_messages(
          with_schema: stub_agent,
          ask: instance_double(RubyLLM::Message, content: { "result" => { "rows_inserted" => 1, "ids" => [ 42 ] } })
        )
      end

      it 'calls with_schema with items on all arrays and completes successfully' do
        described_class.new(pipeline_run).call

        ids_schema = hash_including("items" => anything)
        expect(stub_agent).to have_received(:with_schema).with(
          hash_including(
            "properties" => hash_including(
              "result" => hash_including("properties" => hash_including("ids" => ids_schema))
            )
          )
        )
        expect(Orchestration::ActionRun.last.status).to eq("completed")
      end
    end

    context 'when schema has items without type (regression: Run #69)' do
      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent",
                                    output_schema: {
                                      "type" => "object", "additionalProperties" => false,
                                      "required" => [ "result" ],
                                      "properties" => {
                                        "result" => {
                                          "type" => "object", "additionalProperties" => false,
                                          "properties" => {
                                            "rows_inserted" => { "type" => "integer" },
                                            "ids"           => { "type" => "array", "items" => {} }
                                          }
                                        }
                                      }
                                    })
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive(:with_schema).and_return(stub_agent)
        allow(stub_agent).to receive(:ask)
          .and_raise(RuntimeError, "Invalid schema for response_format 'response': " \
                                   "In context=('properties', 'result', 'properties', 'ids', 'items'), " \
                                   "schema must have a 'type' key.")
      end

      it 'marks the action_run as failed with the Mistral schema error' do
        described_class.new(pipeline_run).call

        store_run = Orchestration::ActionRun.last
        expect(store_run.status).to eq("failed")
        expect(store_run.error).to match(/schema must have a 'type' key/)
      end
    end

    context 'when schema items includes a type (fix for Run #69)' do
      let(:store_schema) do
        {
          "type"                 => "object",
          "additionalProperties" => false,
          "required"             => [ "result" ],
          "properties"           => {
            "result" => {
              "type"                 => "object",
              "additionalProperties" => false,
              "properties"           => {
                "rows_inserted" => { "type" => "integer" },
                "ids"           => { "type" => "array", "items" => { "type" => "integer" } }
              }
            }
          }
        }
      end

      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent", output_schema: store_schema)
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive_messages(
          with_schema: stub_agent,
          ask: instance_double(RubyLLM::Message, content: { "result" => { "rows_inserted" => 1, "ids" => [ 42 ] } })
        )
      end

      it 'calls with_schema with typed items and completes successfully' do
        described_class.new(pipeline_run).call

        ids_schema = hash_including("items" => { "type" => "integer" })
        expect(stub_agent).to have_received(:with_schema).with(
          hash_including(
            "properties" => hash_including(
              "result" => hash_including("properties" => hash_including("ids" => ids_schema))
            )
          )
        )
        expect(Orchestration::ActionRun.last.status).to eq("completed")
      end
    end

    context 'when store agent returns result as non-object (regression: Run #64)' do
      before do
        store_agent_record = create(:orchestration_agent, name: "Records::StoreAgent",
                                    output_schema: {
                                      "type" => "object", "required" => [ "result" ],
                                      "properties" => { "result" => { "type" => "object" } }
                                    })
        store_action = create(:orchestration_action, agent: store_agent_record)
        create(:orchestration_step_action, step: step1, action: store_action, position: 1)

        allow(stub_agent).to receive_messages(with_schema: stub_agent, ask: instance_double(RubyLLM::Message, content: { "result" => [ 1, 2, 3 ] }))
      end

      it 'marks the store action_run as failed with a schema validation error' do
        described_class.new(pipeline_run).call

        store_run = Orchestration::ActionRun.last
        expect(store_run.status).to eq("failed")
        expect(store_run.error).to match(/data\.result must be an object/)
      end
    end

    context 'when an agent action has step params alongside a resolved input' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:classify_agent) { instance_double(RubyLLM::Agent, chat: create(:chat), params: {}) }

      before do
        fetch_action = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        classify_action = create(:orchestration_action, agent: create(:orchestration_agent, name: "Emails::ClassifyAgent"))
        step2 = create(:orchestration_step, pipeline: pipeline, name: "classify", position: 2)

        create(:orchestration_step_action, step: step1, action: fetch_action, position: 1, output_key: "fetch")
        create(:orchestration_step_action,
               step: step2, action: classify_action, position: 1,
               input_mapping: { "emails" => { "from" => "fetch", "path" => "emails" } },
               params: { "mode" => "strict", "limit" => 10 })

        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [ { "id" => "e1" } ] })
        allow(RubyLLM::Agent).to receive(:new).and_return(classify_agent)
        allow(classify_agent).to receive_messages(
          with_model: classify_agent,
          ask: instance_double(RubyLLM::Message, content: "done")
        )
      end

      it 'passes step params merged with the resolved input to the agent ask call' do
        described_class.new(pipeline_run).call
        expect(classify_agent).to have_received(:ask)
          .with(satisfy { |json| JSON.parse(json) == { "mode" => "strict", "limit" => 10, "emails" => [ { "id" => "e1" } ] } })
      end
    end

    context 'when step params and input_mapping share a key' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:classify_agent) { instance_double(RubyLLM::Agent, chat: create(:chat), params: {}) }

      before do
        fetch_action = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        classify_action = create(:orchestration_action, agent: create(:orchestration_agent, name: "Emails::ClassifyAgent"))
        step2 = create(:orchestration_step, pipeline: pipeline, name: "classify", position: 2)

        create(:orchestration_step_action, step: step1, action: fetch_action, position: 1, output_key: "fetch")
        create(:orchestration_step_action,
               step: step2, action: classify_action, position: 1,
               input_mapping: { "emails" => { "from" => "fetch", "path" => "emails" } },
               params: { "emails" => "PARAM_OVERRIDE", "limit" => 5 })

        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [ { "id" => "e1" } ] })
        allow(RubyLLM::Agent).to receive(:new).and_return(classify_agent)
        allow(classify_agent).to receive_messages(
          with_model: classify_agent,
          ask: instance_double(RubyLLM::Message, content: "done")
        )
      end

      it 'input_mapping value wins over the param value on collision' do
        described_class.new(pipeline_run).call
        expect(classify_agent).to have_received(:ask)
          .with(satisfy { |json| JSON.parse(json).fetch("emails") == [ { "id" => "e1" } ] })
      end
    end

    context 'when a step has two parallel actions with distinct output keys' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "consume", position: 2)
        fetch_a = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        fetch_b = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        consume_action = create(:orchestration_action, agent: action.agent)

        create(:orchestration_step_action, step: step1, action: fetch_a, position: 1, output_key: "source_a")
        create(:orchestration_step_action, step: step1, action: fetch_b, position: 2, output_key: "source_b")
        create(:orchestration_step_action,
               step: step2, action: consume_action, position: 1,
               input_mapping: {
                 "a" => { "from" => "source_a" },
                 "b" => { "from" => "source_b" }
               })

        allow(Emails::FetchExecutor).to receive(:call)
          .and_return({ "data" => "alpha" }, { "data" => "beta" })
      end

      it 'both parallel outputs are accessible to the next step via their output_keys' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("completed")
        consume_run = Orchestration::ActionRun.joins(step_action: :step).find_by(steps: { name: "consume" })
        expect(consume_run.input).to eq({ "a" => { "data" => "alpha" }, "b" => { "data" => "beta" } })
      end
    end

    context 'when an input_mapping references a sibling action in the same step' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "process", position: 2)
        sibling_a = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        sibling_b = create(:orchestration_action, agent: action.agent)

        create(:orchestration_step_action, step: step1, action: action, position: 1)
        create(:orchestration_step_action, step: step2, action: sibling_a, position: 1, output_key: "sib_a")
        create(:orchestration_step_action,
               step: step2, action: sibling_b, position: 2, output_key: "sib_b",
               input_mapping: { "data" => { "from" => "sib_a" } })

        allow(stub_agent).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: "result"))
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "result" => [] })
      end

      it 'marks the sibling-referencing action_run failed at resolve-time with UnknownOutputKey' do
        described_class.new(pipeline_run).call
        sib_b_run = Orchestration::ActionRun
          .joins(:step_action)
          .where(step_actions: { output_key: "sib_b" })
          .first
        expect(sib_b_run.status).to eq("failed")
        expect(sib_b_run.error).to include('unknown output key: "sib_a"')
      end

      it 'does not execute the valid sibling when a resolver error marks any action_run in the step failed' do
        described_class.new(pipeline_run).call
        expect(Emails::FetchExecutor).not_to have_received(:call)
      end
    end

    context 'when input_mapping references an unknown output key' do
      before do
        create(:orchestration_step_action,
               step: step1, action: action, position: 1,
               input_mapping: { "x" => { "from" => "nonexistent" } })
      end

      it 'creates the action_run and marks it failed with the resolver message' do
        described_class.new(pipeline_run).call
        expect(Orchestration::ActionRun.count).to eq(1)
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to eq('unknown output key: "nonexistent"')
      end

      it 'marks the pipeline_run as failed' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("failed")
      end
    end

    context 'when input_mapping references a missing path' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        fetch_action = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        classify_action = create(:orchestration_action, agent: action.agent)
        step2 = create(:orchestration_step, pipeline: pipeline, name: "classify", position: 2)

        create(:orchestration_step_action, step: step1, action: fetch_action, position: 1, output_key: "fetch")
        create(:orchestration_step_action,
               step: step2, action: classify_action, position: 1,
               input_mapping: { "x" => { "from" => "fetch", "path" => "nonexistent.deep" } })

        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
      end

      it 'marks the classify action_run failed with the specific MissingPath message' do
        described_class.new(pipeline_run).call
        classify_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .find_by(steps: { name: "classify" })
        expect(classify_run.status).to eq("failed")
        expect(classify_run.error).to include("nonexistent.deep")
      end
    end

    context 'when filter agent returns a bare array (regression: Run #58 TypeError)' do
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "filter",  position: 2)
        step3 = create(:orchestration_step, pipeline: pipeline, name: "ingest",  position: 3)

        filter_agent_record = create(:orchestration_agent, name: "Emails::FilterAgent")

        fetch_action  = create(:orchestration_action, :service_kind, agent_class: "Emails::FetchExecutor")
        filter_action = create(:orchestration_action, agent: filter_agent_record)
        ingest_action = create(:orchestration_action, :service_kind,
                                agent_class: "Orchestration::IngestionExecutor",
                                params: {
                                  "operations" => [
                                    { "type" => "filter_by_ids", "source" => "emails",
                                      "ids_from" => "result.results", "output" => "emails" },
                                    { "type" => "pick", "keys" => [ "emails" ] }
                                  ]
                                })

        create(:orchestration_step_action, step: step1, action: fetch_action,  position: 1)
        create(:orchestration_step_action, step: step2, action: filter_action, position: 1)
        create(:orchestration_step_action, step: step3, action: ingest_action, position: 1)

        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [ { "id" => "e1" } ] })
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: [ { "id" => "e1" } ]))
      end

      it 'completes with empty emails instead of crashing with TypeError' do
        described_class.new(pipeline_run).call

        ingest_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .find_by(steps: { name: "ingest" })

        expect(ingest_run.status).to eq("completed")
        expect(ingest_run.output).to eq({ "emails" => [] })
      end
    end
  end
end
