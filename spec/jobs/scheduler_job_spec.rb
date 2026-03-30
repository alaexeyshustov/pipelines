# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchedulerJob do
  let(:cron_expression) { "* * * * *" } # every minute

  before do
    allow(PipelineRunJob).to receive(:perform_later)
  end

  describe "#perform" do
    context "when a pipeline is enabled with a cron_expression and is due" do
      let!(:pipeline) do
        p = create(:orchestration_pipeline, enabled: true, cron_expression: cron_expression)
        p.update_column(:created_at, 2.hours.ago)
        p
      end

      it "creates a pending pipeline run attributed to the pipeline" do
        described_class.new.perform

        run = Orchestration::PipelineRun.last
        expect(run.pipeline).to eq(pipeline)
        expect(run.triggered_by).to eq("schedule")
        expect(run.status).to eq("pending")
      end

      it "enqueues PipelineRunJob for the created run" do
        described_class.new.perform
        expect(PipelineRunJob).to have_received(:perform_later).with(Orchestration::PipelineRun.last.id)
      end
    end

    context "when a pipeline is disabled" do
      it "does not enqueue a run" do
        create(:orchestration_pipeline, enabled: false, cron_expression: cron_expression)

        expect {
          described_class.new.perform
        }.not_to change(Orchestration::PipelineRun, :count)

        expect(PipelineRunJob).not_to have_received(:perform_later)
      end
    end

    context "when a pipeline has no cron_expression" do
      it "does not enqueue a run" do
        create(:orchestration_pipeline, enabled: true, cron_expression: nil)

        expect {
          described_class.new.perform
        }.not_to change(Orchestration::PipelineRun, :count)

        expect(PipelineRunJob).not_to have_received(:perform_later)
      end
    end

    context "when a pipeline already has a running run" do
      it "does not enqueue another run" do
        pipeline = create(:orchestration_pipeline, enabled: true, cron_expression: cron_expression)
        create(:orchestration_pipeline_run, pipeline: pipeline, status: "running")

        expect {
          described_class.new.perform
        }.not_to change(Orchestration::PipelineRun, :count)

        expect(PipelineRunJob).not_to have_received(:perform_later)
      end
    end

    context "when the next tick is in the future" do
      it "does not enqueue a run" do
        # Use an expression that only runs at midnight, so next run is in the future
        pipeline = create(:orchestration_pipeline, enabled: true, cron_expression: "0 0 * * *")
        # Simulate a completed run that just finished now, so next run is tomorrow midnight
        create(:orchestration_pipeline_run,
               pipeline: pipeline,
               status: "completed",
               finished_at: Time.current)

        expect {
          described_class.new.perform
        }.not_to change(Orchestration::PipelineRun, :count)
      end
    end
  end
end
