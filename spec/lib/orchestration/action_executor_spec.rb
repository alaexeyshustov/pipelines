require "rails_helper"

RSpec.describe Orchestration::ActionExecutor do
  subject(:executor) do
    described_class.new(action_run: action_run, pipeline_run: pipeline_run, prompt_resolver: resolver)
  end

  let(:pipeline)     { create(:orchestration_pipeline) }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: pipeline, status: "running") }
  let(:action_run)   { create(:orchestration_action_run, pipeline_run: pipeline_run, status: "pending") }
  let(:resolver) do
    stub_const("FakePromptResolver", Class.new do
      def call(agent_class) = { "Agent::A" => "system prompt A" }[agent_class]
    end)
    FakePromptResolver.new
  end

  describe "#prompt_for" do
    it "delegates prompt resolution to the injected resolver, passing the agent name through" do
      expect(executor.send(:prompt_for, "Agent::A")).to eq("system prompt A")
    end

    it "returns nil when the resolver resolves no prompt for the agent" do
      expect(executor.send(:prompt_for, "Agent::Missing")).to be_nil
    end
  end
end
