class CreateEvaluationJustifications < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_justifications do |t|
      t.integer :evaluation_result_id, null: false
      t.string :metric_name, null: false
      t.text :justification, null: false

      t.timestamps
    end

    add_index :evaluation_justifications, :evaluation_result_id
    add_foreign_key :evaluation_justifications, :leva_evaluation_results, column: :evaluation_result_id
  end
end
