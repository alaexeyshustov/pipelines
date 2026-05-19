class RenameOrchestrationTables < ActiveRecord::Migration[8.1]
  # SQLite 3.26+ (released 2018-12-01) automatically rewrites FK references in
  # dependent tables when a table is renamed, so no manual FK recreation is needed.
  def change
    rename_table :pipelines,     :orchestration_pipelines
    rename_table :pipeline_runs, :orchestration_pipeline_runs
    rename_table :steps,         :orchestration_steps
    rename_table :actions,       :orchestration_actions
    rename_table :step_actions,  :orchestration_step_actions
    rename_table :action_runs,   :orchestration_action_runs
  end
end
