class AddIndexToLevaPromptsName < ActiveRecord::Migration[7.2]
  def change
    add_index :leva_prompts, :name
  end
end
