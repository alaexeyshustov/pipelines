class AddEnabledToSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :enabled, :boolean, null: false, default: true
  end
end
