
class AddRuntimeFieldsToOrchestrationAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :orchestration_agents, :prompt, :text
    add_column :orchestration_agents, :params, :json, default: {}, null: false
    add_column :orchestration_agents, :output_schema, :json
  end
end
