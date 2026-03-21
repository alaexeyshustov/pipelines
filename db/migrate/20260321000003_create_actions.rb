class CreateActions < ActiveRecord::Migration[8.0]
  def change
    create_table :actions do |t|
      t.string :name, null: false
      t.string :agent_class, null: false
      t.text :description
      t.string :model
      t.json :tools
      t.text :prompt
      t.json :params

      t.timestamps
    end
  end
end
