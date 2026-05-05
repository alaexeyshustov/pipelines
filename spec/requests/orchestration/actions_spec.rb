# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::Actions" do
  describe "GET /orchestration/actions" do
    it "returns 200 and lists actions" do
      create(:orchestration_action, name: "My Action")
      get orchestration_actions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Action")
      expect(response.body).to include("agent")
    end

    it "shows agent name for agent-kind actions" do
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      create(:orchestration_action, name: "My Action", kind: :agent, agent: agent)
      get orchestration_actions_path
      expect(response.body).to match(/href="#{orchestration_agent_path(agent)}"[^>]*>\s*Emails::ClassifyAgent/)
    end

    it "shows pipeline usage count" do
      action = create(:orchestration_action)
      step_action = create(:orchestration_step_action, action: action)
      get orchestration_actions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1")
    end
  end

  describe "GET /orchestration/actions/new" do
    it "returns 200 with form" do
      get new_orchestration_action_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name")
      expect(response.body).to include("kind")
    end
  end

  describe "POST /orchestration/actions" do
    context "with valid params" do
      let(:orchestration_agent) { create(:orchestration_agent, name: "Emails::ClassifyAgent") }
      let(:valid_params) do
        {
          orchestration_action: {
            name: "New Action",
            kind: "agent",
            agent_id: orchestration_agent.id,
            description: "A description",
            prompt: "Classify this email",
            params: '{"key":"value"}'
          }
        }
      end

      it "creates an action and redirects" do
        expect {
          post orchestration_actions_path, params: valid_params
        }.to change(Orchestration::Action, :count).by(1)
        expect(response).to redirect_to(orchestration_actions_path)
      end
    end

    context "with invalid params" do
      it "renders new with 422" do
        post orchestration_actions_path, params: { orchestration_action: { name: "", kind: "agent" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("kind")
      end

      it "falls back to raw params when tools JSON is invalid" do
        agent = create(:orchestration_agent)
        expect {
          post orchestration_actions_path, params: {
            orchestration_action: {
              name: "Test", kind: "agent", agent_id: agent.id, tools: "{invalid json"
            }
          }
        }.to change(Orchestration::Action, :count).by(1)
      end
    end
  end

  describe "GET /orchestration/actions/:id/edit" do
    it "returns 200 with form populated" do
      action = create(:orchestration_action, name: "Edit Me")
      get edit_orchestration_action_path(action)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Me")
    end
  end

  describe "PATCH /orchestration/actions/:id" do
    context "with valid params" do
      it "updates and redirects" do
        action = create(:orchestration_action, name: "Old Name")
        patch orchestration_action_path(action), params: {
          orchestration_action: { name: "New Name" }
        }
        expect(response).to redirect_to(orchestration_actions_path)
        expect(action.reload.name).to eq("New Name")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        action = create(:orchestration_action)
        patch orchestration_action_path(action), params: {
          orchestration_action: { name: "" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /orchestration/actions/:id" do
    it "destroys unused action and redirects" do
      action = create(:orchestration_action)
      expect {
        delete orchestration_action_path(action)
      }.to change(Orchestration::Action, :count).by(-1)
      expect(response).to redirect_to(orchestration_actions_path)
    end

    it "shows error when action is used in a pipeline" do
      action = create(:orchestration_action)
      create(:orchestration_step_action, action: action)
      expect {
        delete orchestration_action_path(action)
      }.not_to change(Orchestration::Action, :count)
      expect(response).to redirect_to(orchestration_actions_path)
      follow_redirect!
      expect(response.body).to include("Cannot delete")
    end
  end
end
