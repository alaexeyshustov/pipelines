require 'rails_helper'

RSpec.describe Orchestration::RuntimeAgentBuilder do
  subject(:builder) { described_class.new(policy: policy, chat: chat) }

  let(:chat) { create(:chat) }

  let(:policy) do
    Orchestration::AgentResolutionPolicy::Result.new(
      model: "mistral-large-latest",
      prompt: "Classify this email",
      tools: [ Records::TempFileTool ],
      output_schema: { "type" => "object" }
    )
  end

  describe '#build' do
    it 'returns a RubyLLM::Agent instance' do
      expect(builder.build).to be_a(RubyLLM::Agent)
    end

    it 'uses the provided chat' do
      expect(builder.build.chat).to eq(chat)
    end

    # RubyLLM::Agent uses `def_delegators :chat`, so `agent.with_model` → `chat.with_model`.
    # We stub the chat directly rather than the agent to avoid creating test doubles.
    it 'applies the policy model to the agent' do
      allow(chat).to receive(:with_model).and_return(chat)
      builder.build
      expect(chat).to have_received(:with_model).with("mistral-large-latest")
    end

    it 'applies the policy tools to the agent' do
      allow(chat).to receive(:with_tools).and_return(chat)
      builder.build
      expect(chat).to have_received(:with_tools).with(Records::TempFileTool, replace: true)
    end

    it 'applies the policy output schema to the agent' do
      allow(chat).to receive(:with_schema).and_return(chat)
      builder.build
      expect(chat).to have_received(:with_schema).with({ "type" => "object" })
    end

    it 'applies the policy prompt as chat instructions' do
      allow(chat).to receive(:with_instructions).and_return(chat)
      builder.build
      expect(chat).to have_received(:with_instructions).with("Classify this email")
    end

    context 'when all policy fields are blank' do
      let(:policy) do
        Orchestration::AgentResolutionPolicy::Result.new(
          model: nil, prompt: nil, tools: [], output_schema: nil
        )
      end

      it 'does not call with_model' do
        allow(chat).to receive(:with_model)
        described_class.new(policy: policy, chat: chat).build
        expect(chat).not_to have_received(:with_model)
      end

      it 'does not call with_tools' do
        allow(chat).to receive(:with_tools)
        described_class.new(policy: policy, chat: chat).build
        expect(chat).not_to have_received(:with_tools)
      end

      it 'does not call with_schema' do
        allow(chat).to receive(:with_schema)
        described_class.new(policy: policy, chat: chat).build
        expect(chat).not_to have_received(:with_schema)
      end

      it 'does not call with_instructions' do
        allow(chat).to receive(:with_instructions)
        described_class.new(policy: policy, chat: chat).build
        expect(chat).not_to have_received(:with_instructions)
      end
    end

    context 'when no chat is provided' do
      it 'creates a new Chat record via Chat.create!' do
        expect {
          described_class.new(policy: policy).build
        }.to change(Chat, :count).by(1)
      end
    end

    def stub_agent_construction(fake_chat:)
      generic_agent = RubyLLM::Agent.allocate
      allow(Orchestration::Agents::EmailsClassifier).to receive(:create)
      allow(fake_chat).to receive(:with_instructions)
      allow(RubyLLM::Agent).to receive(:new).and_return(generic_agent)
      allow(generic_agent).to receive_messages(
        with_model: generic_agent, with_tools: generic_agent,
        with_schema: generic_agent, chat: fake_chat
      )
    end

    it 'always uses RubyLLM::Agent.new regardless of agent name' do
      fake_chat = create(:chat)
      stub_agent_construction(fake_chat:)
      builder.build
      expect(Orchestration::Agents::EmailsClassifier).not_to have_received(:create)
      expect(RubyLLM::Agent).to have_received(:new)
    end
  end
end
