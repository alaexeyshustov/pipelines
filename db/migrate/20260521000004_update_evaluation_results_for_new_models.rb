class UpdateEvaluationResultsForNewModels < ActiveRecord::Migration[8.1]
  def change
    # Add nullable: existing rows in evaluation_evaluation_results cannot be mapped
    # to the new dataset_sample / sample tables without a data migration.
    # In production, backfill these columns before adding NOT NULL constraints.
    add_reference :evaluation_evaluation_results, :dataset_sample, null: true,
                  foreign_key: { to_table: :evaluation_dataset_samples }
    add_reference :evaluation_evaluation_results, :sample, null: true,
                  foreign_key: { to_table: :evaluation_samples }

    remove_reference :evaluation_evaluation_results, :dataset_record,
                     foreign_key: { to_table: :evaluation_dataset_records }
    remove_reference :evaluation_evaluation_results, :runner_result,
                     foreign_key: { to_table: :evaluation_runner_results }
  end
end
