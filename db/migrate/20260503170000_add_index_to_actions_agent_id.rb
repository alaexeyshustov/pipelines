
class AddIndexToActionsAgentId < ActiveRecord::Migration[8.1]
  def change
    add_index :actions, :agent_id
  end
end
