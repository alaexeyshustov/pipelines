# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::PipelineRuns" do
  describe "GET /orchestration/pipelines/:pipeline_id/pipeline_runs" do
    it "returns 200 and lists runs with status, triggered_by, and timestamps" do
      pipeline = create(:orchestration_pipeline, name: "My Pipeline")
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed",
             triggered_by: "manual", started_at: Time.zone.parse("2026-03-01 10:00:00"),
             finished_at: Time.zone.parse("2026-03-01 10:05:00"))

      get orchestration_pipeline_pipeline_runs_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Completed")
      expect(response.body).to include("manual")
    end

    it "shows empty state when no runs exist" do
      pipeline = create(:orchestration_pipeline)

      get orchestration_pipeline_pipeline_runs_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No runs yet")
    end

    it "lists runs in reverse chronological order" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed",
             created_at: 2.hours.ago)
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "failed",
             created_at: 1.hour.ago)

      get orchestration_pipeline_pipeline_runs_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Failed")).to be < response.body.index("Completed")
    end
  end

  describe "GET /orchestration/pipelines/:pipeline_id/pipeline_runs/:id" do
    let(:pipeline) { create(:orchestration_pipeline, name: "My Pipeline") }
    let(:step) { create(:orchestration_step, pipeline: pipeline, name: "Parse Step", position: 1) }
    let(:action) { create(:orchestration_action, name: "Parser Action") }
    let(:step_action) { create(:orchestration_step_action, step: step, action: action, position: 1) }

    it "returns 200 and shows run details" do
      run = create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed",
                   triggered_by: "manual", started_at: Time.zone.parse("2026-03-01 10:00:00"),
                   finished_at: Time.zone.parse("2026-03-01 10:05:00"))

      get orchestration_pipeline_pipeline_run_path(pipeline, run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Completed")
      expect(response.body).to include("manual")
    end

    it "shows step-level derived status for action_runs" do
      run = create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed")
      create(:orchestration_action_run, pipeline_run: run, step_action: step_action,
             status: "completed", started_at: Time.zone.parse("2026-03-01 10:00:00"),
             finished_at: Time.zone.parse("2026-03-01 10:01:00"))

      get orchestration_pipeline_pipeline_run_path(pipeline, run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Parse Step")
      expect(response.body).to include("Parser Action")
    end

    it "shows formatted JSON for action_run input and output" do
      run = create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed")
      create(:orchestration_action_run, pipeline_run: run, step_action: step_action,
             status: "completed", input: { "email" => "test@example.com" },
             output: { "result" => "ok" })

      get orchestration_pipeline_pipeline_run_path(pipeline, run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("test@example.com")
      expect(response.body).to include("result")
    end

    it "shows error text when action_run has an error" do
      run = create(:orchestration_pipeline_run, pipeline: pipeline, status: "failed",
                   error: "Pipeline failed")
      create(:orchestration_action_run, pipeline_run: run, step_action: step_action,
             status: "failed", error: "Action timed out")

      get orchestration_pipeline_pipeline_run_path(pipeline, run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Action timed out")
    end
  end
end
