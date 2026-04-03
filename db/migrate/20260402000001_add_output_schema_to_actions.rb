class AddOutputSchemaToActions < ActiveRecord::Migration[8.1]
  def change
    add_column :actions, :output_schema, :json
  end
end
