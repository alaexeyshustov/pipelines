# This migration comes from leva (originally 20240813172916)
class CreateLevaDatasets < ActiveRecord::Migration[7.2]
  def change
    create_table :leva_datasets do |t|
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end
