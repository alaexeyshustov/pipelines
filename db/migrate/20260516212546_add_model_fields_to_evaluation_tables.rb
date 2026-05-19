class AddModelFieldsToEvaluationTables < ActiveRecord::Migration[8.1]
  def change
    add_column :evaluation_prompts,     :output_schema, :json
    add_column :evaluation_experiments, :sample_model,  :string
    add_column :evaluation_experiments, :evaluation_model, :string
  end
end
