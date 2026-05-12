class CreateEvaluationSyntheticRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_synthetic_records do |t|
      t.string :agent_name, null: false
      t.json   :input,      null: false
      t.timestamps
    end
    add_index :evaluation_synthetic_records, :agent_name
  end
end
