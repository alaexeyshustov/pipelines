class CreateEvaluationMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_metrics do |t|
      t.string :agent_name, null: false
      t.string :name, null: false
      t.text :description, null: false
      t.decimal :weight, null: false, default: "1.0"
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :evaluation_metrics, %i[agent_name name], unique: true
  end
end
