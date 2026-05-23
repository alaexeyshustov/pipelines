# frozen_string_literal: true

class AddExperimentPhasesToEvaluationExperiments < ActiveRecord::Migration[8.1]
  def up
    add_column :evaluation_experiments, :status_str, :string, default: "pending", null: false

    # Map old integer enum values to new string states.
    # 0=pending, 1=running (can't safely resume → failed), 2=completed, 3=failed
    execute(<<~SQL)
      UPDATE evaluation_experiments
      SET status_str = CASE status
        WHEN 2 THEN 'completed'
        WHEN 3 THEN 'failed'
        WHEN 1 THEN 'failed'
        ELSE 'pending'
      END
    SQL

    remove_column :evaluation_experiments, :status
    rename_column :evaluation_experiments, :status_str, :status

    add_column :evaluation_experiments, :pending_samples_count, :integer, default: 0, null: false
    add_column :evaluation_experiments, :pending_evaluations_count, :integer, default: 0, null: false
  end

  def down
    remove_column :evaluation_experiments, :pending_evaluations_count
    remove_column :evaluation_experiments, :pending_samples_count
    remove_column :evaluation_experiments, :status
    add_column :evaluation_experiments, :status, :integer, default: 0
  end
end
