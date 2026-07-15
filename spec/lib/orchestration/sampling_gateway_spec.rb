# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::SamplingGateway do
  let(:orchestration_agent) do
    create(:orchestration_agent,
           name: "Emails::ClassifyAgent",
           model: "mistral-large-latest",
           tools: [ "Records::TempFileTool" ])
  end

  let(:action_record) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }

  before do
    orchestration_agent
    action_record
  end

  describe ".build" do
    it "builds a runnable agent for an existing agent and action" do
      agent = described_class.build(agent_name: "Emails::ClassifyAgent", pipeline_model: nil)

      expect(agent).to be_a(RubyLLM::Agent)
    end

    it "passes tools through the identity tool_transform without requiring RubyLLM-specific shape" do
      identity = ->(tools) { tools }

      agent = described_class.build(
        agent_name: "Emails::ClassifyAgent",
        pipeline_model: nil,
        tool_transform: identity
      )

      expect(agent).to be_a(RubyLLM::Agent)
    end

    it "calls the tool_transform with the resolved tool classes" do
      received = nil
      transform = lambda { |tools|
        received = tools
        tools
      }

      described_class.build(agent_name: "Emails::ClassifyAgent", pipeline_model: nil, tool_transform: transform)

      expect(received).to eq([ Records::TempFileTool ])
    end

    context "with a pipeline_model and prompt_override" do
      let(:build_args) do
        {
          agent_name: "Emails::ClassifyAgent",
          pipeline_model: "mistral-small-latest",
          prompt_override: "Custom instructions."
        }
      end

      it "passes them through to AgentResolutionPolicy" do
        allow(Orchestration::AgentResolutionPolicy).to receive(:new).and_call_original

        described_class.build(**build_args)

        expect(Orchestration::AgentResolutionPolicy).to have_received(:new)
          .with(hash_including(action: action_record, **build_args.except(:agent_name)))
      end
    end

    it "raises Orchestration::AgentNotFound (an ArgumentError subclass) when the agent does not exist" do
      expect(Orchestration::AgentNotFound.ancestors).to include(ArgumentError)
      expect {
        described_class.build(agent_name: "Nonexistent::Agent", pipeline_model: nil)
      }.to raise_error(Orchestration::AgentNotFound, /Nonexistent::Agent/)
    end

    it "raises Orchestration::ActionNotFound (an ArgumentError subclass) when no action exists for the agent" do
      expect(Orchestration::ActionNotFound.ancestors).to include(ArgumentError)
      agent_without_action = create(:orchestration_agent, name: "Emails::NoActionAgent")

      expect {
        described_class.build(agent_name: "Emails::NoActionAgent", pipeline_model: nil)
      }.to raise_error(Orchestration::ActionNotFound, /Emails::NoActionAgent/)

      agent_without_action
    end
  end
end
