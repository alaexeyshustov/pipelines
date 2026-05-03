# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evaluation::Experiments" do
  describe "GET /evaluation/experiments" do
    it "returns 200" do
      get evaluation_experiments_path
      expect(response).to have_http_status(:ok)
    end

    it "lists experiments" do
      experiment = create(:leva_experiment)
      get evaluation_experiments_path
      expect(response.body).to include(experiment.name)
    end
  end

  describe "GET /evaluation/experiments/:id" do
    let(:experiment) { create(:leva_experiment) }

    it "returns 200" do
      get evaluation_experiment_path(experiment)
      expect(response).to have_http_status(:ok)
    end

    it "shows experiment name" do
      get evaluation_experiment_path(experiment)
      expect(response.body).to include(experiment.name)
    end
  end

  describe "POST /evaluation/experiments/:id/improve" do
    let(:experiment) { create(:leva_experiment) }
    let(:new_prompt) { build(:orchestration_prompt) }

    before do
      allow(Evaluation::PromptImprover).to receive(:call).and_return(new_prompt)
    end

    it "redirects to show with notice" do
      post improve_evaluation_experiment_path(experiment)
      expect(response).to redirect_to(evaluation_experiment_path(experiment))
      expect(flash[:notice]).to be_present
    end

    it "calls PromptImprover" do
      post improve_evaluation_experiment_path(experiment)
      expect(Evaluation::PromptImprover).to have_received(:call).with(experiment: experiment)
    end

    context "when PromptImprover raises an error" do
      before do
        allow(Evaluation::PromptImprover).to receive(:call)
          .and_raise(Evaluation::PromptImprover::Error, "LLM call failed")
      end

      it "redirects with alert" do
        post improve_evaluation_experiment_path(experiment)
        expect(response).to redirect_to(evaluation_experiment_path(experiment))
        expect(flash[:alert]).to include("Prompt improvement failed")
      end
    end
  end

  describe "GET /evaluation/experiments/:id/compare/:candidate_id" do
    let(:baseline) { create(:leva_experiment, status: :completed) }
    let(:prompt) { baseline.prompt }

    context "when candidate is completed" do
      let(:candidate) { create(:leva_experiment, status: :completed, prompt: prompt) }

      before do
        allow(Evaluation::Comparison).to receive(:call).and_return(
          Evaluation::Comparison::ComparisonResult.new(
            baseline_score: 3.0,
            candidate_score: 4.0,
            baseline_metrics: { "clarity" => 3.0 },
            candidate_metrics: { "clarity" => 4.0 },
            metric_deltas: { "clarity" => 1.0 },
            overall_delta: 1.0
          )
        )
      end

      it "returns 200" do
        get compare_evaluation_experiment_path(baseline, candidate_id: candidate.id)
        expect(response).to have_http_status(:ok)
      end

      it "renders comparison component" do
        get compare_evaluation_experiment_path(baseline, candidate_id: candidate.id)
        expect(response.body).to include("clarity")
      end
    end

    context "when candidate is pending" do
      let(:candidate) { create(:leva_experiment, status: :pending, prompt: prompt) }

      it "returns 200 with loading state" do
        get compare_evaluation_experiment_path(baseline, candidate_id: candidate.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("pending")
      end
    end
  end

  describe "POST /evaluation/experiments/:id/activate" do
    let(:experiment) { create(:leva_experiment) }

    it "redirects to show with notice" do
      post activate_evaluation_experiment_path(experiment)
      expect(response).to redirect_to(evaluation_experiment_path(experiment))
      expect(flash[:notice]).to be_present
    end

    it "marks the prompt as active in metadata" do
      post activate_evaluation_experiment_path(experiment)
      meta = JSON.parse(experiment.prompt.reload.metadata || "{}")
      expect(meta["active"]).to be(true)
    end
  end
end
