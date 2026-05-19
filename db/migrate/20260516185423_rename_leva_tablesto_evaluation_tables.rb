class RenameLevaTablestoEvaluationTables < ActiveRecord::Migration[8.1]
  def change
    rename_table :leva_datasets,           :evaluation_datasets
    rename_table :leva_dataset_records,    :evaluation_dataset_records
    rename_table :leva_experiments,        :evaluation_experiments
    rename_table :leva_runner_results,     :evaluation_runner_results
    rename_table :leva_evaluation_results, :evaluation_evaluation_results
    rename_table :leva_prompts,            :evaluation_prompts
    drop_table :leva_optimization_runs, if_exists: true
  end
end
