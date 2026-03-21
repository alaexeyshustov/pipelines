class CreateSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :steps do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false
      t.json :input_mapping

      t.timestamps
    end

    add_index :steps, [ :pipeline_id, :position ], unique: true
  end
end
