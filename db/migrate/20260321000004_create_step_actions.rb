class CreateStepActions < ActiveRecord::Migration[8.0]
  def change
    create_table :step_actions do |t|
      t.references :step, null: false, foreign_key: true
      t.references :action, null: false, foreign_key: true
      t.integer :position, null: false
      t.json :params

      t.timestamps
    end

    add_index :step_actions, [ :step_id, :position ], unique: true
  end
end
