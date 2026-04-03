class AddSchemaClassToActions < ActiveRecord::Migration[8.1]
  def change
    add_column :actions, :schema_class, :string
  end
end
