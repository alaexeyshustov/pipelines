# This migration comes from leva (originally 20240813173033)
class CreateLevaDatasetRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :leva_dataset_records do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :leva_datasets }
      t.references :recordable, polymorphic: true, null: false
      t.text :actual_result

      t.timestamps
    end
  end
end
