class CreatePipelineRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_runs do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :triggered_by
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error

      t.timestamps
    end

    add_index :pipeline_runs, :status
  end
end
