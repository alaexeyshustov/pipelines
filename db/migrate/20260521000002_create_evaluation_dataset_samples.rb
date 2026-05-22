class CreateEvaluationDatasetSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_dataset_samples do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :evaluation_datasets }
      t.json :input, null: false
      t.json :expected_tool_calls
      t.integer :source_run_id

      t.timestamps
    end

    add_index :evaluation_dataset_samples, :source_run_id
  end
end
