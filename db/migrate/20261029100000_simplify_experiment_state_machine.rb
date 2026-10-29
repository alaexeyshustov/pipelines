# GH #194: experiments run one per-sample job, so "sampling" and "evaluating" collapse into "running"
# and the two pending counters into `pending_samples_count`. In-flight experiments are not preserved.
class SimplifyExperimentStateMachine < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE evaluation_experiments SET status = 'running' WHERE status IN ('sampling', 'evaluating')"
    remove_column :evaluation_experiments, :pending_evaluations_count
  end

  def down
    add_column :evaluation_experiments, :pending_evaluations_count, :integer, default: 0, null: false
    execute "UPDATE evaluation_experiments SET status = 'evaluating' WHERE status = 'running'"
  end
end
