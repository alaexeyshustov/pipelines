class RemoveChatLevaDatasetRecords < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM leva_dataset_records WHERE recordable_type = 'Chat'"
    execute <<~SQL
      DELETE FROM leva_datasets
      WHERE id NOT IN (SELECT DISTINCT dataset_id FROM leva_dataset_records)
        AND name = 'Historical Conversations'
    SQL
  end

  def down
  end
end
