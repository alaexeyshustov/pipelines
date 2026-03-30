class AddIndexToPipelineRunsPipelineIdCreatedAt < ActiveRecord::Migration[8.1]
  def change
    add_index :pipeline_runs, [ :pipeline_id, :created_at ]
  end
end
