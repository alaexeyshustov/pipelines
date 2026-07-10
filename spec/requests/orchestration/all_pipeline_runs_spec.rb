# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::AllPipelineRuns" do
  describe "GET /orchestration/pipeline_runs" do
    it "returns 200 and lists runs across pipelines newest first" do
      pipeline = create(:orchestration_pipeline, name: "My Pipeline")
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed",
             created_at: 2.days.ago)
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "running",
             created_at: 1.hour.ago)

      get orchestration_pipeline_runs_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Running")).to be < response.body.index("Completed")
    end
  end
end
