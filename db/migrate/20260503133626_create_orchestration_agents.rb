class CreateOrchestrationAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :orchestration_agents do |t|
      t.string :name, null: false
      t.text :description
      t.string :model
      t.json :tools, default: []
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
    add_index :orchestration_agents, :name, unique: true
  end
end
