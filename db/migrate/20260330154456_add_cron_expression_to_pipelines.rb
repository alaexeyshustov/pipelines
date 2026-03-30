class AddCronExpressionToPipelines < ActiveRecord::Migration[8.1]
  def change
    add_column :pipelines, :cron_expression, :string
    remove_column :pipelines, :schedule_interval, :integer
  end
end
