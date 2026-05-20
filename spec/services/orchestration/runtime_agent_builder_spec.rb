require 'rails_helper'

RSpec.describe Orchestration::RuntimeAgentBuilder do
  subject(:builder) { described_class.new(policy: policy) }

  let(:policy) do
    Orchestration::AgentResolutionPolicy::Result.new(
      model: "mistral-large-latest",
      prompt: "Classify this email",
      tools: [ Records::TempFileTool ],
      params: { "mode" => "fast" },
      output_schema: { "type" => "object" },
      generation_schema: { "type" => "object" }
    )
  end

  describe '#build' do
    it 'returns a RubyLLM::Agent instance' do
      expect(builder.build).to be_a(RubyLLM::Agent)
    end

    it 'always uses RubyLLM::Agent.new regardless of agent name' do
      allow(Emails::ClassifyAgent).to receive(:create)

      generic_agent = instance_double(RubyLLM::Agent)
      allow(RubyLLM::Agent).to receive(:new).and_return(generic_agent)
      allow(generic_agent).to receive_messages(with_model: generic_agent, with_tools: generic_agent,
                                               with_schema: generic_agent,
                                               chat: instance_double(Chat, with_instructions: nil))

      builder.build

      expect(Emails::ClassifyAgent).not_to have_received(:create)
      expect(RubyLLM::Agent).to have_received(:new)
    end
  end
end
