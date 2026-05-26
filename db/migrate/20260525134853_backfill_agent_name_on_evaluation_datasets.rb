class BackfillAgentNameOnEvaluationDatasets < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE evaluation_datasets SET agent_name = name WHERE agent_name IS NULL"
  end

  def down; end
end
