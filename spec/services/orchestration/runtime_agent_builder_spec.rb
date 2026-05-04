require 'rails_helper'

RSpec.describe Orchestration::RuntimeAgentBuilder do
  subject(:builder) do
    described_class.new(
      action: action,
      pipeline_model: "mistral-large",
      step_params: { "limit" => 5 }
    )
  end

  let(:agent_record) do
    create(:orchestration_agent,
           name: "Reusable Classifier",
           model: "mistral-small",
           tools: [ "Records::TempFileTool" ],
           prompt: "Classify this email",
           params: { "mode" => "fast" },
           output_schema: { "type" => "object" })
  end
  let(:action) { create(:orchestration_action, agent: agent_record) }

  describe '#build' do
    it 'does not delegate to a legacy RubyLLM::Agent subclass even when the agent name matches one' do # rubocop:disable RSpec/ExampleLength
      legacy_agent_record = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      legacy_action = create(:orchestration_action, agent: legacy_agent_record)
      allow(Emails::ClassifyAgent).to receive(:create)

      generic_agent = instance_double(RubyLLM::Agent)
      allow(RubyLLM::Agent).to receive(:new).and_return(generic_agent)
      allow(generic_agent).to receive_messages(with_model: generic_agent, with_tools: generic_agent,
                                               with_params: generic_agent, with_schema: generic_agent,
                                               chat: instance_double(Chat, with_instructions: nil))

      described_class.new(action: legacy_action).build

      expect(Emails::ClassifyAgent).not_to have_received(:create)
      expect(RubyLLM::Agent).to have_received(:new)
    end
  end

  describe '#snapshot' do
    it 'returns a hash with the resolved model' do
      expect(builder.snapshot[:model]).to eq("mistral-large")
    end

    it 'falls back to the agent model when pipeline model is absent' do
      builder_no_pipeline_model = described_class.new(action: action)
      expect(builder_no_pipeline_model.snapshot[:model]).to eq("mistral-small")
    end

    it 'returns the resolved prompt' do
      expect(builder.snapshot[:prompt]).to eq("Classify this email")
    end

    it 'returns tools as an array of strings' do
      expect(builder.snapshot[:tools]).to eq([ "Records::TempFileTool" ])
    end

    it 'returns merged params (agent defaults overridden by step params)' do
      expect(builder.snapshot[:params]).to eq({ "mode" => "fast", "limit" => 5 })
    end

    it 'returns the output schema' do
      expect(builder.snapshot[:output_schema]).to eq({ "type" => "object" })
    end
  end
end
