class RenameOrchestrationTables < ActiveRecord::Migration[8.1]
  def change
    rename_table :pipelines,     :orchestration_pipelines
    rename_table :pipeline_runs, :orchestration_pipeline_runs
    rename_table :steps,         :orchestration_steps
    rename_table :actions,       :orchestration_actions
    rename_table :step_actions,  :orchestration_step_actions
    rename_table :action_runs,   :orchestration_action_runs
  end
end
