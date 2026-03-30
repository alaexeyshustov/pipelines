class AddIndexToPipelinesEnabledAndCronExpression < ActiveRecord::Migration[8.1]
  def change
    add_index :pipelines, [ :enabled, :cron_expression ]
  end
end
