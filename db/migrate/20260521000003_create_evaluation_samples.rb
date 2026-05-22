class CreateEvaluationSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_samples do |t|
      t.references :experiment, null: false, foreign_key: { to_table: :evaluation_experiments }
      t.references :dataset_sample, null: false, foreign_key: { to_table: :evaluation_dataset_samples }
      t.references :prompt, null: false, foreign_key: { to_table: :evaluation_prompts }
      t.json :tool_calls
      t.text :output

      t.timestamps
    end
  end
end
