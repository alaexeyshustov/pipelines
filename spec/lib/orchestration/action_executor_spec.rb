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

  describe "#call with an agent that has message-scoped email tools" do
    let(:agent)  { create(:orchestration_agent, name: "Emails::ClassifyAgent", model: "mistral-large-latest", tools: [ "Emails::GetTool" ]) }
    let(:action) { create(:orchestration_action, kind: :agent, agent: agent) }
    let(:step_action) { create(:orchestration_step_action, action: action) }
    let(:action_run) do
      create(:orchestration_action_run, pipeline_run: pipeline_run, step_action: step_action, status: "pending", input: { "emails" => [] })
    end

    before do
      stub_request(:post, "https://api.mistral.ai/v1/chat/completions").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: "chatcmpl-1", object: "chat.completion", model: "mistral-large-latest",
          choices: [ { index: 0, message: { role: "assistant", content: "done" }, finish_reason: "stop" } ],
          usage: { prompt_tokens: 10, completion_tokens: 2, total_tokens: 12 }
        }.to_json
      )
    end

    it "stores the tool class names in the agent snapshot, not tool instances" do
      executor.call

      expect(action_run.reload.agent_snapshot["tools"]).to eq([ "Emails::GetTool" ])
    end
  end
end
