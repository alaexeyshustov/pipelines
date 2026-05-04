class AddAgentSnapshotToActionRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :action_runs, :agent_snapshot, :json
  end
end
