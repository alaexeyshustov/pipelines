require 'rails_helper'

RSpec.describe Orchestration::AgentResolutionPolicy do
  subject(:policy) do
    described_class.new(action: action, pipeline_model: "mistral-large").resolve
  end

  let(:agent_record) do
    create(:orchestration_agent,
           model: "mistral-small",
           tools: [ "Records::TempFileTool" ],
           prompt: "Classify this email",
           output_schema: { "type" => "object" })
  end
  let(:action) { create(:orchestration_action, agent: agent_record) }

  describe '#model' do
    it 'prefers pipeline_model over agent model' do
      expect(policy.model).to eq("mistral-large")
    end

    it 'falls back to agent model when pipeline_model is absent' do
      result = described_class.new(action: action).resolve
      expect(result.model).to eq("mistral-small")
    end
  end

  describe '#prompt' do
    it 'returns the agent prompt' do
      expect(policy.prompt).to eq("Classify this email")
    end

    it 'prefers prompt_override over agent prompt' do
      result = described_class.new(action: action, prompt_override: "Override prompt").resolve
      expect(result.prompt).to eq("Override prompt")
    end
  end

  describe '#tools' do
    it 'returns constantized tool classes' do
      expect(policy.tools).to eq([ Records::TempFileTool ])
    end

    it 'returns tool_classes directly when provided' do
      result = described_class.new(action: action, tool_classes: [ Records::TempFileTool ]).resolve
      expect(result.tools).to eq([ Records::TempFileTool ])
    end

    it 'resolves no tools when tool_classes is an empty array' do
      result = described_class.new(action: action, tool_classes: []).resolve
      expect(result.tools).to eq([])
    end

    it 'passes caller-supplied anonymous subclasses through unvalidated' do
      stub_const('BlockedTempFileTool', Class.new(Records::TempFileTool))
      blocked = BlockedTempFileTool
      result = described_class.new(action: action, tool_classes: [ blocked ]).resolve
      expect(result.tools).to eq([ blocked ])
    end

    it 'resolves Emails::ClassifyTool to the registry subclass bound to the classifier' do
      allow(agent_record).to receive(:tools).and_return([ 'Emails::ClassifyTool' ])
      expect(policy.tools.first.classifier).to eq(Orchestration::Agents::EmailsClassifier)
    end

    it 'resolves through Orchestration::ToolResolver.lookup' do
      allow(Orchestration::ToolResolver).to receive(:lookup).and_call_original
      policy
      expect(Orchestration::ToolResolver).to have_received(:lookup).with('Records::TempFileTool')
    end

    [ 'Kernel::Exec', 'Records::NonExistentTool', 'Records::ModelResolver', 'Emails::Adapters::GmailAdapter' ].each do |name|
      it "raises ArgumentError for stored tool #{name}" do
        allow(agent_record).to receive(:tools).and_return([ name ])
        expect { policy }.to raise_error(ArgumentError, /Unknown tool class: #{Regexp.escape(name)}/)
      end
    end

    it 'does not accept a Class stored in the agent tools' do
      allow(agent_record).to receive(:tools).and_return([ Records::TempFileTool ])
      expect { policy }.to raise_error(ArgumentError)
    end
  end

  describe '#output_schema' do
    it 'returns the agent output schema' do
      expect(policy.output_schema).to eq({ "type" => "object" })
    end

    it 'returns nil when agent has no output schema' do
      allow(agent_record).to receive(:output_schema).and_return(nil)
      expect(described_class.new(action: action).resolve.output_schema).to be_nil
    end
  end
end
