# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::Actions", type: :request do
  describe "GET /orchestration/actions" do
    it "returns 200 and lists actions" do
      action = create(:orchestration_action, name: "My Action", agent_class: "EmailClassifyAgent")
      get orchestration_actions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Action")
      expect(response.body).to include("EmailClassifyAgent")
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
      expect(response.body).to include("agent_class")
    end
  end

  describe "POST /orchestration/actions" do
    context "with valid params" do
      let(:valid_params) do
        {
          orchestration_action: {
            name: "New Action",
            agent_class: "EmailClassifyAgent",
            description: "A description",
            model: "mistral-small",
            tools: '["EmailClassifier"]',
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
        post orchestration_actions_path, params: { orchestration_action: { name: "", agent_class: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("agent_class")
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
          orchestration_action: { name: "New Name", agent_class: "EmailClassifyAgent" }
        }
        expect(response).to redirect_to(orchestration_actions_path)
        expect(action.reload.name).to eq("New Name")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        action = create(:orchestration_action)
        patch orchestration_action_path(action), params: {
          orchestration_action: { name: "", agent_class: "" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
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
