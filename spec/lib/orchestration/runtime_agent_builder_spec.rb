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
      expect(chat).to have_received(:with_model).with("mistral-large-latest", provider: nil, assume_model_exists: false)
    end

    context 'with a provider/model policy model' do
      let(:policy) do
        Orchestration::AgentResolutionPolicy::Result.new(model: "ollama/qwen3", prompt: nil, tools: [], output_schema: nil)
      end

      it 'pins the provider and resolves the local model without a registry entry' do
        expect(builder.build.chat.reload.model).to have_attributes(model_id: "qwen3", provider: "ollama")
      end
    end

    it 'applies the policy tools to the agent' do
      allow(chat).to receive(:with_tools).and_return(chat)
      builder.build
      expect(chat).to have_received(:with_tools).with(nil).ordered
      expect(chat).to have_received(:with_tools).with(Records::TempFileTool).ordered
    end

    it 'applies the policy output schema to the agent' do
      allow(chat).to receive(:with_schema).and_return(chat)
      builder.build
      expect(chat).to have_received(:with_schema).with({ "type" => "object" })
    end

    # Assumes the planned constant Orchestration::RuntimeAgentBuilder::UNTRUSTED_INPUT_PREAMBLE (a String)
    # and that the preamble and the prompt are joined into one instruction, preamble first.
    describe 'untrusted input preamble' do
      let(:preamble) { described_class::UNTRUSTED_INPUT_PREAMBLE }

      def applied_instructions(built_chat)
        captured = nil
        allow(built_chat).to receive(:with_instructions) { |text, **| captured = text }.and_return(built_chat)
        yield
        captured
      end

      it 'defines a preamble that says input fields are data and instructions in them are ignored' do
        expect(preamble).to be_a(String).and match(/data/i).and match(/ignore/i)
      end

      it 'puts the preamble before the agent prompt' do
        text = applied_instructions(chat) { builder.build }

        expect(text).to start_with(preamble)
        expect(text).to end_with("Classify this email")
        expect(text.index(preamble)).to be < text.index("Classify this email")
      end

      it 'puts the preamble before a prompt override' do
        text = applied_instructions(chat) do
          overridden = Orchestration::AgentResolutionPolicy::Result.new(
            model: "mistral-large-latest", prompt: "Override prompt", tools: [], output_schema: nil
          )
          described_class.new(policy: overridden, chat: chat).build
        end

        expect(text).to start_with(preamble)
        expect(text).to end_with("Override prompt")
      end

      it 'applies the preamble alone when the prompt is empty' do
        text = applied_instructions(chat) do
          empty = Orchestration::AgentResolutionPolicy::Result.new(model: nil, prompt: nil, tools: [], output_schema: nil)
          described_class.new(policy: empty, chat: chat).build
        end

        expect(text.strip).to eq(preamble.strip)
      end

      it 'applies the preamble when the prompt is a blank string' do
        text = applied_instructions(chat) do
          blank = Orchestration::AgentResolutionPolicy::Result.new(model: nil, prompt: "   ", tools: [], output_schema: nil)
          described_class.new(policy: blank, chat: chat).build
        end

        expect(text.strip).to eq(preamble.strip)
      end

      it 'does not repeat the preamble inside the prompt text' do
        text = applied_instructions(chat) { builder.build }
        expect(text.scan(preamble).size).to eq(1)
      end
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

      it 'still calls with_instructions, for the untrusted-input preamble' do
        allow(chat).to receive(:with_instructions).and_return(chat)
        described_class.new(policy: policy, chat: chat).build
        expect(chat).to have_received(:with_instructions)
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
