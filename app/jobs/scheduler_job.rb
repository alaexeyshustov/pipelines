# frozen_string_literal: true

class SchedulerJob < ApplicationJob
  def perform
    running_ids      = Orchestration::PipelineRun.where(status: "running").select(:pipeline_id)
    latest_completed = load_latest_completed_times

    schedulable_pipelines.where.not(id: running_ids).find_each do |pipeline|
      schedule_pipeline_if_due(pipeline, latest_completed)
    end
  end

  private

  def load_latest_completed_times
    Orchestration::PipelineRun.where(status: "completed").group(:pipeline_id).maximum(:finished_at)
  end

  def schedulable_pipelines
    Orchestration::Pipeline.where(enabled: true).where.not(cron_expression: [ nil, "" ])
  end

  def schedule_pipeline_if_due(pipeline, latest_completed)
    reference_time = latest_completed[pipeline.id] || pipeline.created_at
    next_time      = pipeline.next_run_at(from: reference_time)
    return unless next_time && next_time <= Time.current

    pipeline_run = pipeline.pipeline_runs.create!(status: "pending", triggered_by: "schedule")
    PipelineRunJob.perform_later(pipeline_run.id)
  end
end
