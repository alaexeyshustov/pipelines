class AddInitialInputSchemaToPipelines < ActiveRecord::Migration[8.1]
  def change
    add_column :pipelines, :initial_input_schema, :json
  end
end
