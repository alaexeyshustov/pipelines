class AddInputSchemaToAgentsAndRemoveParams < ActiveRecord::Migration[8.1]
  def change
    add_column :orchestration_agents, :input_schema, :json

    remove_column :orchestration_agents,      :params, :text
    remove_column :orchestration_actions,     :params, :text
    remove_column :orchestration_step_actions, :params, :text
  end
end
