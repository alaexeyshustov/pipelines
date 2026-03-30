class PipelineRunJob < ApplicationJob
  def perform(pipeline_run_id)
    pipeline_run = Orchestration::PipelineRun.find(pipeline_run_id)
    Orchestration::PipelineRunner.new(pipeline_run).call
  end
end
