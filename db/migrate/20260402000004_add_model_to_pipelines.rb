class AddModelToPipelines < ActiveRecord::Migration[8.1]
  def change
    add_column :pipelines, :model, :string
  end
end
