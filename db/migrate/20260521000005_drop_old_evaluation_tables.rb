class DropOldEvaluationTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :evaluation_runner_results
    drop_table :evaluation_dataset_records
    drop_table :evaluation_synthetic_records
  end

  def down
    create_table :evaluation_synthetic_records do |t|
      t.string :agent_name, null: false
      t.json :input, null: false
      t.json :expected_tool_calls
      t.integer :source_run_id
      t.timestamps
    end

    create_table :evaluation_dataset_records do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :evaluation_datasets }
      t.string :recordable_type, null: false
      t.integer :recordable_id, null: false
      t.text :actual_result
      t.timestamps
    end

    create_table :evaluation_runner_results do |t|
      t.references :experiment, foreign_key: { to_table: :evaluation_experiments }
      t.references :dataset_record, null: false, foreign_key: { to_table: :evaluation_dataset_records }
      t.references :prompt, null: false, foreign_key: { to_table: :evaluation_prompts }
      t.integer :prompt_version
      t.text :prediction
      t.string :runner_class, null: false
      t.timestamps
    end
  end
end
