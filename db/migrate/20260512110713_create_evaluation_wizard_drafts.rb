class CreateEvaluationWizardDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_wizard_drafts do |t|
      t.string  :session_token, null: false
      t.integer :step, default: 1, null: false
      t.json    :payload
      t.timestamps
    end
    add_index :evaluation_wizard_drafts, :session_token, unique: true
  end
end
