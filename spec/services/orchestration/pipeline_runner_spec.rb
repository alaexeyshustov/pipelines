require 'rails_helper'

RSpec.describe Orchestration::PipelineRunner do
  let(:pipeline)     { create(:orchestration_pipeline) }
  let(:step1)        { create(:orchestration_step, pipeline: pipeline, name: "extract", position: 1) }
  let(:action)       { create(:orchestration_action, agent_class: "Emails::ClassifyAgent") }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: pipeline, status: "pending") }
  let(:stub_agent) { instance_double(Emails::ClassifyAgent) }

  before do
    allow(Emails::ClassifyAgent).to receive(:create).and_return(stub_agent)
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
        action.update!(model: 'openai-gpt4')
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
        action.update!(model: 'openai-gpt4')
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
        action.update!(model: nil)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:with_model)
      end

      it 'does not call with_model on the agent' do
        described_class.new(pipeline_run).call
        expect(stub_agent).not_to have_received(:with_model)
      end
    end

    context 'when the action has a schema_class' do
      before do
        action.update!(schema_class: "ApplicationMailsSchema")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:with_schema).and_return(stub_agent)
      end

      it 'calls with_schema on the agent with the constantized class' do
        described_class.new(pipeline_run).call
        expect(stub_agent).to have_received(:with_schema).with(ApplicationMailsSchema)
      end
    end

    context 'when a Leva::Prompt exists for the agent class' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        Leva::Prompt.create!(
          name: "Emails::ClassifyAgent",
          system_prompt: "Custom Leva prompt for classifier",
          user_prompt: "{{input}}"
        )
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'applies the Leva system_prompt as instructions' do
        described_class.new(pipeline_run).call
        expect(chat).to have_received(:with_instructions).with("Custom Leva prompt for classifier")
      end
    end

    context 'when a Leva::Prompt exists and action also has a prompt' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        Leva::Prompt.create!(
          name: "Emails::ClassifyAgent",
          system_prompt: "Leva wins over action prompt",
          user_prompt: "{{input}}"
        )
        action.update!(prompt: "Action-level prompt")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'prefers the Leva prompt over the action prompt' do
        described_class.new(pipeline_run).call
        expect(chat).to have_received(:with_instructions).with("Leva wins over action prompt")
      end
    end

    context 'when no Leva::Prompt exists but the action has a prompt' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        action.update!(prompt: "Action-level fallback prompt")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'falls back to the action prompt' do
        described_class.new(pipeline_run).call
        expect(chat).to have_received(:with_instructions).with("Action-level fallback prompt")
      end
    end

    context 'when no Leva::Prompt and no action prompt' do
      let(:chat) { instance_spy(Chat, id: nil) }

      before do
        allow(stub_agent).to receive(:chat).and_return(chat)
        action.update!(prompt: nil)
        create(:orchestration_step_action, step: step1, action: action, position: 1)
      end

      it 'does not call with_instructions on the chat' do
        described_class.new(pipeline_run).call
        expect(chat).not_to have_received(:with_instructions)
      end
    end

    context 'with an executable action' do
      before do
        executable_action = create(:orchestration_action, agent_class: "Emails::FetchExecutor")
        create(:orchestration_step_action, step: step1, action: executable_action, position: 1)
      end

      it 'calls the executable and stores its Hash output' do
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "emails" => [] })
      end
    end

    context 'with an executable action that has params' do
      before do
        ops = { "operations" => [ { "type" => "pick", "keys" => [ "emails" ] } ] }
        ingest_action = create(:orchestration_action,
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
        action3       = create(:orchestration_action, agent_class: "Emails::ClassifyAgent")
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
        action2 = create(:orchestration_action, agent_class: "Emails::ClassifyAgent")
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

    context 'when the action has an output_schema and the output is invalid' do
      before do
        action.update!(output_schema: { "type" => "object", "required" => [ "result" ],
                                        "properties" => { "result" => { "type" => "array" } } })
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        # agent returns a natural-language string — not parseable as a JSON array
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: "I need more information."))
      end

      it 'marks the ActionRun as failed with a schema error' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to match(/must be an array/)
      end

      it 'marks the PipelineRun as failed' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("failed")
      end
    end

    context 'when the action has an output_schema and the output is valid JSON' do
      before do
        action.update!(output_schema: { "type" => "object", "required" => [ "result" ],
                                        "properties" => { "result" => { "type" => "array" } } })
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: '[{"id":1}]'))
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

    context 'with two steps and input_mapping on the second step' do
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "transform", position: 2)
        action2 = create(:orchestration_action, agent_class: "Emails::ClassifyAgent")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        create(:orchestration_step_action, step: step2, action: action2, position: 1)
        allow(stub_agent).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: "step output"))
        step2.update!(input_mapping: {
          "processed" => { "from_step" => "extract", "path" => "result", "merge" => "concat" }
        })
      end

      it 'passes step1 output as resolved input to the step2 ActionRun' do
        described_class.new(pipeline_run).call
        step2_action_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .where(steps: { name: "transform" }).first
        expect(step2_action_run.input).to eq({ "processed" => "step output" })
      end

      it 'completes both steps and the PipelineRun' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("completed")
        expect(Orchestration::ActionRun.where(status: "completed").count).to eq(2)
      end
    end

    context 'when pipeline_run has initial_input' do
      before do
        pipeline_run.update!(initial_input: { "date" => "2026-04-03", "providers" => [ "gmail" ] })
        step1.update!(input_mapping: { "fetch_date" => { "from_step" => "initial", "path" => "date" } })
        executable_action = create(:orchestration_action, agent_class: "Emails::FetchExecutor")
        create(:orchestration_step_action, step: step1, action: executable_action, position: 1)
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [] })
      end

      it 'injects initial_input as step 0 output so step 1 can reference it via input_mapping' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.input).to eq({ "fetch_date" => "2026-04-03" })
      end
    end

    context 'with three steps where step 3 needs step 1 output (accumulation)' do
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "filter",  position: 2)
        step3 = create(:orchestration_step, pipeline: pipeline, name: "ingest",  position: 3)

        fetch_action  = create(:orchestration_action, agent_class: "Emails::FetchExecutor")
        filter_action = create(:orchestration_action, agent_class: "Emails::FilterAgent")
        ingest_action = create(:orchestration_action,
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

        # filter_content is what the LLM returns before run_agent wraps it in { "result" => ... }
        allow(Emails::FetchExecutor).to receive(:call).and_return({ "emails" => [ { "id" => "e1" } ] })
        allow(Emails::FilterAgent).to receive(:create).and_return(stub_agent)
        allow(stub_agent).to receive(:ask)
          .and_return(instance_double(RubyLLM::Message, content: { "results" => [ { "id" => "e1" } ] }))
      end

      it 'accumulates all previous step outputs so step 3 can access step 1 data' do
        described_class.new(pipeline_run).call

        ingest_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .find_by(steps: { name: "ingest" })

        expect(ingest_run.output).to eq({ "emails" => [ { "id" => "e1" } ] })
      end
    end
  end
end
