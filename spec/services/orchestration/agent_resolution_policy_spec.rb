require 'rails_helper'

RSpec.describe Orchestration::AgentResolutionPolicy do
  subject(:policy) do
    described_class.call(
      action: action,
      pipeline_model: "mistral-large",
      step_params: { "limit" => 5 }
    )
  end

  let(:agent_record) do
    create(:orchestration_agent,
           model: "mistral-small",
           tools: [ "Records::TempFileTool" ],
           prompt: "Classify this email",
           params: { "mode" => "fast" },
           output_schema: { "type" => "object" })
  end
  let(:action) { create(:orchestration_action, agent: agent_record) }

  describe '#model' do
    it 'prefers pipeline_model over agent model' do
      expect(policy.model).to eq("mistral-large")
    end

    it 'falls back to agent model when pipeline_model is absent' do
      result = described_class.call(action: action)
      expect(result.model).to eq("mistral-small")
    end
  end

  describe '#prompt' do
    it 'returns the agent prompt' do
      expect(policy.prompt).to eq("Classify this email")
    end

    it 'prefers prompt_override over agent prompt' do
      result = described_class.call(action: action, prompt_override: "Override prompt")
      expect(result.prompt).to eq("Override prompt")
    end
  end

  describe '#tools' do
    it 'returns constantized tool classes' do
      expect(policy.tools).to eq([ Records::TempFileTool ])
    end

    it 'returns tool_classes directly when provided' do
      result = described_class.call(action: action, tool_classes: [ Records::TempFileTool ])
      expect(result.tools).to eq([ Records::TempFileTool ])
    end

    it 'raises ArgumentError when a tool is outside allowed namespaces' do
      allow(agent_record).to receive(:tools).and_return([ "Kernel::Exec" ])
      expect { policy }.to raise_error(ArgumentError, /outside allowed namespaces/)
    end

    it 'raises ArgumentError when a tool class cannot be found' do
      allow(agent_record).to receive(:tools).and_return([ "Records::NonExistentTool" ])
      expect { policy }.to raise_error(ArgumentError, /NonExistentTool/)
    end
  end

  describe '#params' do
    it 'merges agent params with step_params (step_params win)' do
      expect(policy.params).to eq({ "mode" => "fast", "limit" => 5 })
    end

    it 'returns only step_params when agent has no params' do
      allow(agent_record).to receive(:params).and_return(nil)
      result = described_class.call(action: action, step_params: { "limit" => 3 })
      expect(result.params).to eq({ "limit" => 3 })
    end
  end

  describe '#output_schema' do
    it 'returns the agent output schema' do
      expect(policy.output_schema).to eq({ "type" => "object" })
    end

    it 'returns nil when agent has no output schema' do
      allow(agent_record).to receive(:output_schema).and_return(nil)
      expect(described_class.call(action: action).output_schema).to be_nil
    end
  end

  describe '#generation_schema' do
    it 'returns the agent output schema' do
      expect(policy.generation_schema).to eq({ "type" => "object" })
    end
  end
end
