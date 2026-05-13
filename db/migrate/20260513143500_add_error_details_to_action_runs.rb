class AddErrorDetailsToActionRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :action_runs, :error_details, :json
  end
end
