class CreateActionRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :action_runs do |t|
      t.references :pipeline_run, null: false, foreign_key: true
      t.references :step_action, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.json :input
      t.json :output
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :action_runs, :status
  end
end
