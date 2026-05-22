class CreateEvaluationDatasetSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_dataset_samples do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :evaluation_datasets }
      t.json :input, null: false
      t.json :expected_tool_calls
      t.integer :source_run_id

      t.timestamps
    end

    # Unique per-dataset so concurrent seed runs cannot create duplicates.
    add_index :evaluation_dataset_samples, %i[dataset_id source_run_id],
              unique: true,
              where: "source_run_id IS NOT NULL",
              name: "index_eval_dataset_samples_on_dataset_and_source_run"
  end
end
