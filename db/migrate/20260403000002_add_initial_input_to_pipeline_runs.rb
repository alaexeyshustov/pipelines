class AddInitialInputToPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :pipeline_runs, :initial_input, :json
  end
end
