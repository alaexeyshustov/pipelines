class SchedulerJob < ApplicationJob
  def perform
    active_ids      = Orchestration::PipelineRun.in_progress.select(:pipeline_id)
    latest_finished = load_latest_finished_times

    schedulable_pipelines.where.not(id: active_ids).find_each do |pipeline|
      schedule_pipeline_if_due(pipeline, latest_finished)
    end
  end

  private

  # The latest finish of a run in any terminal state: after a failed run the next one waits for the next tick too.
  def load_latest_finished_times
    Orchestration::PipelineRun.where(status: Orchestration::PipelineRun::TERMINAL_STATUSES).group(:pipeline_id).maximum(:finished_at)
  end

  def schedulable_pipelines
    Orchestration::Pipeline.where(enabled: true).where.not(cron_expression: [ nil, "" ])
  end

  def schedule_pipeline_if_due(pipeline, latest_finished)
    reference_time = latest_finished[pipeline.id] || pipeline.created_at
    next_time      = pipeline.next_run_at(from: reference_time)
    return unless next_time && next_time <= Time.current

    pipeline_run = pipeline.pipeline_runs.create!(status: "pending", triggered_by: "schedule")
    PipelineRunJob.perform_later(pipeline_run.id)
  end
end
