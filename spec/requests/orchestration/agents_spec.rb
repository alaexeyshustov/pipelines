# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::Agents" do
  describe "GET /orchestration/agents" do
    it "returns 200 and lists agents" do
      create(:orchestration_agent, name: "Emails::ClassifyAgent", enabled: true)
      get orchestration_agents_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Emails::ClassifyAgent")
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
            name: "Emails::ClassifyAgent",
            description: "Classifies emails",
            model: "mistral-small",
            tools: "[]"
          }
        }
      end

      it "creates an agent and redirects" do
        expect {
          post orchestration_agents_path, params: valid_params
        }.to change(Orchestration::Agent, :count).by(1)
        expect(response).to redirect_to(orchestration_agents_path)
      end
    end

    context "with invalid params" do
      it "renders new with 422" do
        post orchestration_agents_path, params: { orchestration_agent: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /orchestration/agents/:id/edit" do
    it "returns 200 with form populated" do
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      get edit_orchestration_agent_path(agent)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Emails::ClassifyAgent")
    end
  end

  describe "PATCH /orchestration/agents/:id" do
    context "with valid params" do
      it "updates and redirects" do
        agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
        patch orchestration_agent_path(agent), params: {
          orchestration_agent: { name: "Emails::ClassifyAgent", description: "Updated" }
        }
        expect(response).to redirect_to(orchestration_agents_path)
        expect(agent.reload.description).to eq("Updated")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
        patch orchestration_agent_path(agent), params: { orchestration_agent: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /orchestration/agents/:id" do
    it "destroys unreferenced agent and redirects" do
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      expect {
        delete orchestration_agent_path(agent)
      }.to change(Orchestration::Agent, :count).by(-1)
      expect(response).to redirect_to(orchestration_agents_path)
    end

    it "shows error when agent is referenced by an action" do
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      create(:orchestration_action, agent_class: agent.name)
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
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent", enabled: true)
      patch toggle_orchestration_agent_path(agent)
      expect(response).to redirect_to(orchestration_agents_path)
      expect(agent.reload.enabled).to be false
    end
  end
end
