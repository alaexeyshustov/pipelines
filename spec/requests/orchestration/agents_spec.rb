# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::Agents" do
  describe "GET /orchestration/agents" do
    it "returns 200 and lists agents" do
      create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier", enabled: true)
      get orchestration_agents_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Orchestration::Agents::EmailsClassifier")
    end

    it "shows action usage count per agent" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      create(:orchestration_action, name: "Action One", kind: :agent, agent: agent)
      create(:orchestration_action, name: "Action Two", kind: :agent, agent: agent)
      get orchestration_agents_path
      expect(response.body).to include("2 actions")
    end

    it "links agent name to show page" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      get orchestration_agents_path
      expect(response.body).to include("href=\"#{orchestration_agent_path(agent)}\"")
      expect(response.body).to match(/href="#{orchestration_agent_path(agent)}"[^>]*>\s*Orchestration::Agents::EmailsClassifier/)
    end
  end

  describe "GET /orchestration/agents/new" do
    it "returns 200 with form" do
      get new_orchestration_agent_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name")
    end
  end

  describe "POST /orchestration/agents" do
    context "with valid params" do
      let(:valid_params) do
        {
          orchestration_agent: {
            name: "Orchestration::Agents::EmailsClassifier",
            description: "Classifies emails",
            model: "mistral-small",
            tools: [],
            prompt: "Classify this payload",
            output_schema: '{"type":"object","required":["result"],"properties":{"result":{"type":"array"}}}'
          }
        }
      end

      it "creates an agent and redirects" do # rubocop:disable RSpec/MultipleExpectations
        expect {
          post orchestration_agents_path, params: valid_params
        }.to change(Orchestration::Agent, :count).by(1)
        expect(response).to redirect_to(orchestration_agents_path)
        expect(Orchestration::Agent.last.prompt).to eq("Classify this payload")
        expect(Orchestration::Agent.last.output_schema).to eq(
          "type" => "object",
          "required" => [ "result" ],
          "properties" => { "result" => { "type" => "array" } }
        )
      end # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
    end

    context "with invalid params" do
      it "renders new with 422" do
        post orchestration_agents_path, params: { orchestration_agent: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "preserves valid fields when output_schema JSON is invalid" do
        post orchestration_agents_path, params: {
          orchestration_agent: {
            name: "Orchestration::Agents::EmailsClassifier",
            tools: [ "Records::TempFileTool" ],
            output_schema: "{invalid"
          }
        }

        agent = Orchestration::Agent.last
        expect(agent.tools).to eq([ "Records::TempFileTool" ])
        expect(agent.output_schema).to be_nil
      end
    end
  end

  describe "GET /orchestration/agents/:id" do
    it "returns 200 and shows agent name" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      get orchestration_agent_path(agent)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Orchestration::Agents::EmailsClassifier")
    end

    it "lists actions that reference this agent" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      create(:orchestration_action, name: "Classify Email Step", kind: :agent, agent: agent)
      get orchestration_agent_path(agent)
      expect(response.body).to include("Classify Email Step")
    end

    it "shows pipeline name for actions attached to pipelines" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      action = create(:orchestration_action, name: "Classify Email Step", kind: :agent, agent: agent)
      step_action = create(:orchestration_step_action, action: action)
      get orchestration_agent_path(agent)
      expect(response.body).to include(step_action.step.pipeline.name)
    end

    it "deduplicates pipeline name when action appears in multiple steps of the same pipeline" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      action = create(:orchestration_action, name: "Classify Email Step", kind: :agent, agent: agent)
      pipeline = create(:orchestration_pipeline)
      step_a = create(:orchestration_step, pipeline: pipeline)
      step_b = create(:orchestration_step, pipeline: pipeline)
      create(:orchestration_step_action, action: action, step: step_a)
      create(:orchestration_step_action, action: action, step: step_b)
      get orchestration_agent_path(agent)
      expect(response.body.scan(pipeline.name).size).to eq(1)
    end

    it "shows empty state when no actions reference the agent" do
      agent = create(:orchestration_agent, name: "Unused Agent")
      get orchestration_agent_path(agent)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No actions")
    end
  end

  describe "GET /orchestration/agents/:id/edit" do
    it "returns 200 with form populated" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      get edit_orchestration_agent_path(agent)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Orchestration::Agents::EmailsClassifier")
    end
  end

  describe "PATCH /orchestration/agents/:id" do
    context "with valid params" do
      it "updates and redirects" do
        agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
        patch orchestration_agent_path(agent), params: {
          orchestration_agent: { name: "Orchestration::Agents::EmailsClassifier", description: "Updated" }
        }
        expect(response).to redirect_to(orchestration_agents_path)
        expect(agent.reload.description).to eq("Updated")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
        patch orchestration_agent_path(agent), params: { orchestration_agent: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /orchestration/agents/:id" do
    it "destroys unreferenced agent and redirects" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      expect {
        delete orchestration_agent_path(agent)
      }.to change(Orchestration::Agent, :count).by(-1)
      expect(response).to redirect_to(orchestration_agents_path)
    end

    it "shows error when agent is referenced by an action" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      create(:orchestration_action, kind: :agent, agent: agent)
      expect {
        delete orchestration_agent_path(agent)
      }.not_to change(Orchestration::Agent, :count)
      expect(response).to redirect_to(orchestration_agents_path)
      follow_redirect!
      expect(response.body).to include("Cannot delete")
    end
  end

  describe "PATCH /orchestration/agents/:id/toggle" do
    it "toggles enabled state and redirects" do
      agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier", enabled: true)
      patch toggle_orchestration_agent_path(agent)
      expect(response).to redirect_to(orchestration_agents_path)
      expect(agent.reload.enabled).to be false
    end
  end
end
