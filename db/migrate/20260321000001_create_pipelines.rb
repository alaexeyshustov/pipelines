class CreatePipelines < ActiveRecord::Migration[8.0]
  def change
    create_table :pipelines do |t|
      t.string :name, null: false
      t.text :description
      t.integer :schedule_interval
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
  end
end
