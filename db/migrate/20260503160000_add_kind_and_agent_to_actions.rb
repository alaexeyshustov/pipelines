# frozen_string_literal: true

class AddKindAndAgentToActions < ActiveRecord::Migration[8.1]
  def change
    add_column :actions, :kind, :string, null: false, default: "service"
    add_column :actions, :agent_id, :integer, null: true
    add_foreign_key :actions, :orchestration_agents, column: :agent_id
    change_column_null :actions, :agent_class, true
  end
end
