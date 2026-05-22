# frozen_string_literal: true

class AddExperimentPhasesToEvaluationExperiments < ActiveRecord::Migration[8.1]
  def up
    remove_column :evaluation_experiments, :status
    add_column :evaluation_experiments, :status, :string, default: "pending", null: false
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
