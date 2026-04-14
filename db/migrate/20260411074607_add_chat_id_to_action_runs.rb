class AddChatIdToActionRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :action_runs, :chat_id, :integer
    add_index :action_runs, :chat_id
    add_foreign_key :action_runs, :chats, on_delete: :nullify
  end
end
