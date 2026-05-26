# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evaluation::Prompts" do
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
