class AddAgentNameToEvaluationDatasets < ActiveRecord::Migration[8.1]
  def change
    add_column :evaluation_datasets, :agent_name, :string
  end
end
