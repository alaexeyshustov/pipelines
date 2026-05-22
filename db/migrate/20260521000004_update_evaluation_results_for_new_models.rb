class UpdateEvaluationResultsForNewModels < ActiveRecord::Migration[8.1]
  def change
    add_reference :evaluation_evaluation_results, :dataset_sample,
                  null: false, default: 0,
                  foreign_key: { to_table: :evaluation_dataset_samples }
    add_reference :evaluation_evaluation_results, :sample,
                  null: false, default: 0,
                  foreign_key: { to_table: :evaluation_samples }

    change_column_default :evaluation_evaluation_results, :dataset_sample_id, from: 0, to: nil
    change_column_default :evaluation_evaluation_results, :sample_id, from: 0, to: nil

    remove_reference :evaluation_evaluation_results, :dataset_record,
                     foreign_key: { to_table: :evaluation_dataset_records }
    remove_reference :evaluation_evaluation_results, :runner_result,
                     foreign_key: { to_table: :evaluation_runner_results }
  end
end
