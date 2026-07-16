
class DropLegacyColumnsFromActions < ActiveRecord::Migration[8.1]
  def up
    remove_column :actions, :prompt
    remove_column :actions, :model
    remove_column :actions, :tools
    remove_column :actions, :output_schema
    remove_column :actions, :input_schema
    remove_column :actions, :schema_class
  end

  def down
    add_column :actions, :prompt,        :text
    add_column :actions, :model,         :string
    add_column :actions, :tools,         :json
    add_column :actions, :output_schema, :json
    add_column :actions, :input_schema,  :json
    add_column :actions, :schema_class,  :string
  end
end
