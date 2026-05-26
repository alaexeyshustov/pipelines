# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evaluation::Experiments" do
  describe "GET /evaluation/experiments" do
    it "returns 200" do
      get evaluation_experiments_path
      expect(response).to have_http_status(:ok)
    end

    it "lists experiments" do
      experiment = create(:evaluation_experiment)
      get evaluation_experiments_path
      expect(response.body).to include(experiment.name)
    end
  end

  describe "GET /evaluation/experiments/:id" do
    let(:experiment) { create(:evaluation_experiment) }

    it "returns 200" do
      get evaluation_experiment_path(experiment)
      expect(response).to have_http_status(:ok)
    end

    it "shows experiment name" do
      get evaluation_experiment_path(experiment)
      expect(response.body).to include(experiment.name)
    end

    it "shows the status badge" do
      get evaluation_experiment_path(experiment)
      expect(response.body).to include(experiment.status.to_s)
    end

    it "shows records evaluated count" do
      get evaluation_experiment_path(experiment)
      expect(response.body).to include("Records evaluated")
    end

    it "shows Metrics section" do
      get evaluation_experiment_path(experiment)
      expect(response.body).to include("Metrics")
    end

    context "when metrics exist for the agent" do
      let!(:metric) do # rubocop:disable RSpec/LetSetup
        create(:evaluation_metric, agent_name: experiment.prompt.name, name: "Accuracy", description: "Correct output")
      end

      it "lists the metric name" do
        get evaluation_experiment_path(experiment)
        expect(response.body).to include("Accuracy")
      end

      it "shows 'no results' when no eval results exist" do
        get evaluation_experiment_path(experiment)
        expect(response.body).to include("no results")
      end

        it "shows the average metric score" do
          dataset_sample = create(:evaluation_dataset_sample, dataset: experiment.dataset)
          sample = create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample)
          eval_result = Evaluation::EvaluationResult.create!(
            experiment: experiment, dataset_sample: dataset_sample,
            sample: sample, evaluator_class: "Evaluation::Evaluators::LLMJudgeEval", score: 4.0
          )
          Evaluation::Justification.create!(evaluation_result: eval_result, metric_name: "Accuracy", justification: "Good")
          get evaluation_experiment_path(experiment)
          expect(response.body).to include("4.00")
        end

        it "shows overall average" do
          dataset_sample = create(:evaluation_dataset_sample, dataset: experiment.dataset)
          sample = create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample)
          eval_result = Evaluation::EvaluationResult.create!(
            experiment: experiment, dataset_sample: dataset_sample,
            sample: sample, evaluator_class: "Evaluation::Evaluators::LLMJudgeEval", score: 4.0
          )
          Evaluation::Justification.create!(evaluation_result: eval_result, metric_name: "Accuracy", justification: "Good")
          get evaluation_experiment_path(experiment)
          expect(response.body).to include("Overall average")
        end
      end
    end

  describe "POST /evaluation/experiments/:id/improve" do
    let(:experiment) { create(:evaluation_experiment) }
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
    let(:baseline) { create(:evaluation_experiment, status: :completed) }
    let(:prompt) { baseline.prompt }

    context "when candidate is completed" do
      let(:candidate) { create(:evaluation_experiment, status: :completed, prompt: prompt) }

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
      let(:candidate) { create(:evaluation_experiment, status: :pending, prompt: prompt) }

      it "returns 200 with loading state" do
        get compare_evaluation_experiment_path(baseline, candidate_id: candidate.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("pending")
      end
    end
  end

  describe "POST /evaluation/experiments/:id/activate" do
    let(:experiment) { create(:evaluation_experiment) }

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

  describe "GET /evaluation/experiments/new" do
    it "returns 200" do
      get new_evaluation_experiment_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the step nav with 'Agent & Prompt' label" do
      get new_evaluation_experiment_path
      expect(response.body).to include("Agent")
    end

    it "accepts a step param and still returns 200" do
      get new_evaluation_experiment_path(step: 2)
      expect(response).to have_http_status(:ok)
    end

    it "creates a wizard draft and stores token in session" do
      get new_evaluation_experiment_path
      expect(session[:wizard_token]).to be_present
    end
  end

  describe "POST /evaluation/experiments" do
    it "redirects to step 2 after step 1 submission" do
      post evaluation_experiments_path, params: {
        current_step: 1,
        wizard: { agent_name: "Emails::ClassifyAgent", experiment_name: "My Exp", prompt_id: "" }
      }
      expect(response).to redirect_to(new_evaluation_experiment_path(step: 2))
    end

    it "persists agent_name in draft payload" do
      post evaluation_experiments_path, params: {
        current_step: 1,
        wizard: { agent_name: "Emails::ClassifyAgent", experiment_name: "My Exp", prompt_id: "" }
      }
      token = session[:wizard_token]
      draft = Evaluation::WizardDraft.find_by(session_token: token)
      expect(draft.payload["agent_name"]).to eq("Emails::ClassifyAgent")
    end

    it "redirects to step 3 after step 2 (no agent in draft)" do
      post evaluation_experiments_path, params: { current_step: 2 }
      expect(response).to redirect_to(new_evaluation_experiment_path(step: 3))
    end

    context "when submitting step 4 (final review)" do
      let!(:dataset) { create(:evaluation_dataset) }
      let!(:prompt)  { create(:orchestration_prompt) }

      before do
        create(:evaluation_metric, agent_name: prompt.name, active: true)
        allow(Evaluation::ExperimentJob).to receive(:perform_later)
      end

      def navigate_to_step4(prompt:, dataset:)
        post evaluation_experiments_path, params: { current_step: 1, wizard: { agent_name: prompt.name, experiment_name: "Eval Exp", prompt_id: prompt.id.to_s } }
        post evaluation_experiments_path, params: { current_step: 2 }
        post evaluation_experiments_path, params: { current_step: 3, wizard: { dataset_id: dataset.id.to_s } }
      end

      it "creates an experiment and redirects to show page" do
        navigate_to_step4(prompt: prompt, dataset: dataset)
        expect {
          post evaluation_experiments_path, params: { current_step: 4 }
        }.to change(Evaluation::Experiment, :count).by(1)
        expect(response).to redirect_to(evaluation_experiment_path(Evaluation::Experiment.last))
      end

      it "enqueues Evaluation::ExperimentJob on completion" do
        navigate_to_step4(prompt: prompt, dataset: dataset)
        post evaluation_experiments_path, params: { current_step: 4 }
        expect(Evaluation::ExperimentJob).to have_received(:perform_later).once
      end

      it "clears wizard_token from session on completion" do
        navigate_to_step4(prompt: prompt, dataset: dataset)
        post evaluation_experiments_path, params: { current_step: 4 }
        expect(session[:wizard_token]).to be_nil
      end
    end

    context "when metrics are deactivated between step 2 and step 4 (race condition)" do
      let!(:dataset) { create(:evaluation_dataset) }
      let!(:prompt)  { create(:orchestration_prompt) }

      before { allow(Evaluation::ExperimentJob).to receive(:perform_later) }

      it "re-renders with unprocessable_content instead of raising 500" do
        metric = create(:evaluation_metric, agent_name: prompt.name, active: true)
        post evaluation_experiments_path, params: { current_step: 1, wizard: { agent_name: prompt.name, experiment_name: "Race", prompt_id: prompt.id.to_s } }
        post evaluation_experiments_path, params: { current_step: 2 }
        post evaluation_experiments_path, params: { current_step: 3, wizard: { dataset_id: dataset.id.to_s } }
        metric.update!(active: false)
        post evaluation_experiments_path, params: { current_step: 4 }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when posting step 2 with no active metrics for the agent" do
      let!(:prompt) { create(:orchestration_prompt) }

      it "re-renders step 2 with unprocessable_entity status" do
        post evaluation_experiments_path, params: {
          current_step: 1, wizard: { agent_name: prompt.name, experiment_name: "Eval", prompt_id: prompt.id.to_s }
        }
        post evaluation_experiments_path, params: { current_step: 2 }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not advance the draft past step 2" do
        post evaluation_experiments_path, params: {
          current_step: 1, wizard: { agent_name: prompt.name, experiment_name: "Eval", prompt_id: prompt.id.to_s }
        }
        post evaluation_experiments_path, params: { current_step: 2 }
        token = session[:wizard_token]
        draft = Evaluation::WizardDraft.find_by(session_token: token)
        expect(draft.step).to eq(2)
      end
    end
  end

  describe "GET /evaluation/experiments/:id/status_frame" do
    let!(:experiment) { create(:evaluation_experiment) }

    it "returns 200" do
      get status_frame_evaluation_experiment_path(experiment)
      expect(response).to have_http_status(:ok)
    end

    it "renders the status badge partial" do
      get status_frame_evaluation_experiment_path(experiment)
      expect(response.body).to include(experiment.status.to_s)
    end
  end

  describe "GET /evaluation/experiments/:id/metrics/:metric_name" do
    let(:experiment) { create(:evaluation_experiment) }
    let(:metric_name) { "Accuracy" }

    it "returns 200" do
      get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
      expect(response).to have_http_status(:ok)
    end

    it "shows the metric name as title" do
      get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
      expect(response.body).to include(metric_name)
    end

    it "shows empty state when no results" do
      get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
      expect(response.body).to include("No evaluation results")
    end

    context "when evaluation results exist for the metric" do
      let!(:sample) do
        ds = create(:evaluation_dataset_sample, dataset: experiment.dataset)
        create(:evaluation_sample, experiment: experiment, dataset_sample: ds, output: "Predicted text")
      end
      let!(:eval_result) do
        Evaluation::EvaluationResult.create!(
          experiment: experiment, dataset_sample: sample.dataset_sample,
          sample: sample, evaluator_class: "Evaluation::Evaluators::LLMJudgeEval", score: 3.5
        )
      end
      let!(:justification) do # rubocop:disable RSpec/LetSetup
        Evaluation::Justification.create!(
          evaluation_result: eval_result, metric_name: metric_name,
          justification: "Partially correct response."
        )
      end

      it "shows the score" do
        get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
        expect(response.body).to include("3.50")
      end

      it "shows the agent output" do
        get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
        expect(response.body).to include("Predicted text")
      end

      it "shows the justification" do
        get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
        expect(response.body).to include("Partially correct response.")
      end

      it "does not include results for other metrics" do
        Evaluation::Justification.create!(
          evaluation_result: eval_result, metric_name: "Other metric",
          justification: "Other justification."
        )
        get metric_results_evaluation_experiment_path(experiment, metric_name: metric_name)
        expect(response.body).not_to include("Other justification.")
      end
    end
  end

  describe "GET /evaluation/experiments/prompt_content" do
    let!(:prompt) do
      create(:orchestration_prompt, system_prompt: "You are helpful.", user_prompt: "{{input}}")
    end

    it "returns 200 with the prompt fields as JSON" do
      get prompt_content_evaluation_experiments_path, params: { prompt_id: prompt.id }
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["system_prompt"]).to eq("You are helpful.")
      expect(data["user_prompt"]).to eq("{{input}}")
    end

    it "returns 404 when prompt_id is not found" do
      get prompt_content_evaluation_experiments_path, params: { prompt_id: 9_999_999 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /evaluation/experiments/fork_prompt" do
    let!(:based_on) do
      create(:orchestration_prompt, name: "Emails::ClassifyAgent",
             system_prompt: "Classify this.", user_prompt: "{{input}}")
    end

    it "creates a new prompt version" do
      expect {
        post fork_prompt_evaluation_experiments_path,
             params: { based_on_prompt_id: based_on.id,
                       system_prompt: "Updated.", user_prompt: "{{input}}" },
             as: :json
      }.to change(Evaluation::Prompt, :count).by(1)
    end

    it "returns the new prompt id and version" do
      post fork_prompt_evaluation_experiments_path,
           params: { based_on_prompt_id: based_on.id,
                     system_prompt: "Updated.", user_prompt: "{{input}}" },
           as: :json
      data = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(data["id"]).to be_present
      expect(data["version"]).to be > based_on.version
    end

    it "uses the edited system_prompt" do
      post fork_prompt_evaluation_experiments_path,
           params: { based_on_prompt_id: based_on.id,
                     system_prompt: "Edited system.", user_prompt: "{{input}}" },
           as: :json
      expect(Evaluation::Prompt.last.system_prompt).to eq("Edited system.")
    end

    it "preserves the agent name from the base prompt" do
      post fork_prompt_evaluation_experiments_path,
           params: { based_on_prompt_id: based_on.id, user_prompt: "{{input}}" },
           as: :json
      expect(Evaluation::Prompt.last.name).to eq("Emails::ClassifyAgent")
    end

    context "when based_on_prompt_id is not found" do
      it "returns 422 and does not create a prompt" do
        expect {
          post fork_prompt_evaluation_experiments_path,
               params: { based_on_prompt_id: 9_999_999 },
               as: :json
        }.not_to change(Evaluation::Prompt, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /evaluation/experiments/prompt_versions" do
    let!(:prompt) { create(:orchestration_prompt, name: "classify_agent") }

    it "returns 200 with JSON array" do
      get prompt_versions_evaluation_experiments_path, params: { agent_name: "classify_agent" }
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to be_an(Array)
      expect(data.first["id"]).to eq(prompt.id)
    end

    it "returns empty array for unknown agent" do
      get prompt_versions_evaluation_experiments_path, params: { agent_name: "unknown_agent" }
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe "DELETE /evaluation/experiments/:id" do
    context "when the experiment is completed" do
      let!(:experiment) { create(:evaluation_experiment, status: :completed) }

      it "destroys the experiment" do
        expect {
          delete evaluation_experiment_path(experiment)
        }.to change(Evaluation::Experiment, :count).by(-1)
      end

      it "redirects to the experiments index with a notice" do
        delete evaluation_experiment_path(experiment)
        expect(response).to redirect_to(evaluation_experiments_path)
        expect(flash[:notice]).to be_present
      end
    end

    context "when the experiment is completed and has associated samples and results" do
      let!(:experiment) { create(:evaluation_experiment, status: :completed) }
      let!(:sample) do
        ds = create(:evaluation_dataset_sample, dataset: experiment.dataset)
        create(:evaluation_sample, experiment: experiment, dataset_sample: ds)
      end

      before do
        Evaluation::EvaluationResult.create!(
          experiment: experiment, dataset_sample: sample.dataset_sample,
          sample: sample, evaluator_class: "Evaluation::Evaluators::LLMJudgeEval", score: 4.0
        )
      end

      it "destroys the experiment along with its samples and results" do
        expect {
          delete evaluation_experiment_path(experiment)
        }.to change(Evaluation::Experiment, :count).by(-1)
          .and change(Evaluation::Sample, :count).by(-1)
          .and change(Evaluation::EvaluationResult, :count).by(-1)
      end
    end

    context "when the experiment is pending" do
      let!(:experiment) { create(:evaluation_experiment, status: :pending) }

      it "does not destroy the experiment" do
        expect {
          delete evaluation_experiment_path(experiment)
        }.not_to change(Evaluation::Experiment, :count)
      end

      it "redirects to the index with an alert" do
        delete evaluation_experiment_path(experiment)
        expect(response).to redirect_to(evaluation_experiments_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "when the experiment is in progress" do
      let!(:experiment) { create(:evaluation_experiment, status: :sampling) }

      it "does not destroy the experiment" do
        expect {
          delete evaluation_experiment_path(experiment)
        }.not_to change(Evaluation::Experiment, :count)
      end

      it "redirects to the index with an alert" do
        delete evaluation_experiment_path(experiment)
        expect(response).to redirect_to(evaluation_experiments_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /evaluation/experiments/snapshot_agent_prompt" do
    let(:agent) { create(:orchestration_agent, name: "Emails::ClassifyAgent", prompt: "You are a classifier.") }

    before { agent }

    it "creates a new evaluation prompt" do
      expect {
        post snapshot_agent_prompt_evaluation_experiments_path,
             params: { agent_name: "Emails::ClassifyAgent" },
             as: :json
      }.to change(Evaluation::Prompt, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it "returns the prompt id and version" do
      post snapshot_agent_prompt_evaluation_experiments_path,
           params: { agent_name: "Emails::ClassifyAgent" },
           as: :json

      data = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(data["id"]).to eq(Evaluation::Prompt.last.id)
      expect(data["version"]).to be_present
    end

    it "stores the agent prompt as system_prompt" do
      post snapshot_agent_prompt_evaluation_experiments_path,
           params: { agent_name: "Emails::ClassifyAgent" },
           as: :json

      prompt = Evaluation::Prompt.last
      expect(prompt.name).to eq("Emails::ClassifyAgent")
      expect(prompt.system_prompt).to eq("You are a classifier.")
    end

    it "sets the default user_prompt template" do
      post snapshot_agent_prompt_evaluation_experiments_path,
           params: { agent_name: "Emails::ClassifyAgent" },
           as: :json

      expect(Evaluation::Prompt.last.user_prompt).to eq("{{input}}")
    end

    context "when agent has no prompt" do
      let(:empty_agent) { create(:orchestration_agent, name: "EmptyAgent", prompt: nil) }

      before { empty_agent }

      it "returns 422 and does not create a prompt" do
        expect {
          post snapshot_agent_prompt_evaluation_experiments_path,
               params: { agent_name: "EmptyAgent" },
               as: :json
        }.not_to change(Evaluation::Prompt, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when agent does not exist" do
      it "returns 422" do
        post snapshot_agent_prompt_evaluation_experiments_path,
             params: { agent_name: "NonExistent" },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
