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
