# GH #248: a run whose PipelineRunJob died (a deploy, a crash) must not block new runs forever. PipelineRunner and the
# per-item executor loops touch heartbeat_at; an in-progress run whose heartbeat (else started_at, else created_at) is
# older than Orchestration::PipelineRun::STALE_AFTER no longer counts as active. This table has no FTS triggers, so a
# plain add_column is safe.
class AddHeartbeatAtToOrchestrationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :orchestration_pipeline_runs, :heartbeat_at, :datetime
  end
end
