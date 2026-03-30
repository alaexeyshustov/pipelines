# frozen_string_literal: true

class SchedulerJob < ApplicationJob
  def perform
    running_ids = Orchestration::PipelineRun.where(status: "running").select(:pipeline_id)
    latest_completed = Orchestration::PipelineRun
      .where(status: "completed")
      .group(:pipeline_id)
      .maximum(:finished_at)

    Orchestration::Pipeline
      .where(enabled: true)
      .where.not(cron_expression: [ nil, "" ])
      .where.not(id: running_ids)
      .each do |pipeline|
        reference_time = latest_completed[pipeline.id] || pipeline.created_at
        next_time = pipeline.next_run_at(from: reference_time)
        next unless next_time && next_time <= Time.current

        pipeline_run = pipeline.pipeline_runs.create!(status: "pending", triggered_by: "schedule")
        PipelineRunJob.perform_later(pipeline_run.id)
      end
  end
end
