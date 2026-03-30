# frozen_string_literal: true

class SchedulerJob < ApplicationJob
  def perform
    Orchestration::Pipeline
      .where(enabled: true)
      .where.not(cron_expression: [ nil, "" ])
      .each do |pipeline|
        next if pipeline.pipeline_runs.exists?(status: "running")

        reference_time = pipeline.pipeline_runs
          .where(status: "completed")
          .order(finished_at: :desc)
          .pick(:finished_at) || pipeline.created_at

        next_time = pipeline.next_run_at(from: reference_time)
        next unless next_time && next_time <= Time.current

        pipeline_run = pipeline.pipeline_runs.create!(
          status: "pending",
          triggered_by: "schedule"
        )
        PipelineRunJob.perform_later(pipeline_run.id)
      end
  end
end
