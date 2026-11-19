require "rails_helper"

RSpec.describe "Evaluation::Prompts" do
  def activation_path(prompt, action) = "/evaluation/prompts/#{prompt.id}/#{action}"

  describe "GET /evaluation/prompts" do
    it "returns 200" do
      get evaluation_prompts_path
      expect(response).to have_http_status(:ok)
    end

    it "lists all prompts" do
      prompt = create(:orchestration_prompt)
      get evaluation_prompts_path
      expect(response.body).to include(prompt.name)
    end

    it "shows prompt versions" do
      prompt = create(:orchestration_prompt)
      get evaluation_prompts_path
      expect(response.body).to include("v#{prompt.version}")
    end
  end

  describe "GET /evaluation/prompts (activation controls)" do
    it "shows an Active column header" do
      create(:orchestration_prompt)
      get evaluation_prompts_path
      expect(response.body).to include("Active")
    end

    it "offers Activate for an inactive version and Deactivate for the active one" do
      active = create(:orchestration_prompt, :active, name: "AgentA", version: 1)
      inactive = create(:orchestration_prompt, name: "AgentA", version: 2)
      get evaluation_prompts_path
      expect(response.body).to include(activation_path(inactive, :activate), activation_path(active, :deactivate))
      expect(response.body).not_to include(activation_path(active, :activate))
    end
  end

  describe "POST /evaluation/prompts/:id/activate" do
    context "when the version is a fresh draft" do
      let(:prompt) { create(:orchestration_prompt, name: "AgentA") }

      it "is refused with an alert and stays inactive" do
        post activation_path(prompt, :activate)
        expect(response).to redirect_to(evaluation_prompts_path)
        expect(flash[:alert]).to be_present
        expect(prompt.reload.active).to be(false)
      end
    end

    context "when the version has a completed experiment" do
      let(:prompt) { create(:orchestration_prompt, name: "AgentA", version: 2) }
      let!(:old) { create(:orchestration_prompt, :active, name: "AgentA", version: 1) }

      before { create(:evaluation_experiment, prompt: prompt, status: :completed) }

      it "redirects with a notice" do
        post activation_path(prompt, :activate)
        expect(response).to redirect_to(evaluation_prompts_path)
        expect(flash[:notice]).to be_present
      end

      it "activates it and deactivates the previous version" do
        post activation_path(prompt, :activate)
        expect(Evaluation::Prompt.where(id: [ prompt.id, old.id ]).order(:version).pluck(:active)).to eq([ false, true ])
      end
    end

    context "when the version was activated before" do
      let(:prompt) { create(:orchestration_prompt, name: "AgentA", activated_at: 1.day.ago) }

      it "re-activates it without a completed experiment" do
        post activation_path(prompt, :activate)
        expect(prompt.reload.active).to be(true)
      end
    end
  end

  describe "POST /evaluation/prompts/:id/deactivate" do
    it "deactivates the active version so the agent default applies" do
      prompt = create(:orchestration_prompt, :active, name: "AgentA")
      post activation_path(prompt, :deactivate)
      expect(response).to redirect_to(evaluation_prompts_path)
      expect(prompt.reload.active).to be(false)
      expect(Evaluation::Prompt.active_for_agent("AgentA")).to be_nil
    end

    it "is a no-op for an inactive version" do
      prompt = create(:orchestration_prompt, name: "AgentA", activated_at: 1.day.ago)
      expect { post activation_path(prompt, :deactivate) }.not_to(change { prompt.reload.attributes })
      expect(response).to redirect_to(evaluation_prompts_path)
    end
  end

  describe "GET /evaluation/prompts/compare" do
    context "when both prompts have completed experiments" do
      let(:prompt_a) { create(:orchestration_prompt, name: "TestAgent") }
      let(:prompt_b) { create(:orchestration_prompt, name: "TestAgent") }
      let(:dataset)  { create(:evaluation_dataset) }
      let!(:exp_a)   { create(:evaluation_experiment, prompt: prompt_a, dataset: dataset, status: :completed) }
      let!(:exp_b)   { create(:evaluation_experiment, prompt: prompt_b, dataset: dataset, status: :completed) }

      it "redirects to the experiment compare page" do
        get compare_evaluation_prompts_path, params: { prompt_a_id: prompt_a.id, prompt_b_id: prompt_b.id }
        expect(response).to redirect_to(compare_evaluation_experiment_path(exp_a, candidate_id: exp_b.id))
      end
    end

    context "when prompt_a_id is missing" do
      it "redirects to prompts index with alert" do
        get compare_evaluation_prompts_path, params: { prompt_b_id: 1 }
        expect(response).to redirect_to(evaluation_prompts_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "when a prompt does not exist" do
      it "redirects to prompts index with alert" do
        get compare_evaluation_prompts_path, params: { prompt_a_id: 999_999, prompt_b_id: 999_998 }
        expect(response).to redirect_to(evaluation_prompts_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "when prompts lack completed experiments" do
      let(:prompt_a) { create(:orchestration_prompt) }
      let(:prompt_b) { create(:orchestration_prompt) }

      it "redirects to prompts index with alert" do
        get compare_evaluation_prompts_path, params: { prompt_a_id: prompt_a.id, prompt_b_id: prompt_b.id }
        expect(response).to redirect_to(evaluation_prompts_path)
        expect(flash[:alert]).to be_present
      end
    end
  end
end
