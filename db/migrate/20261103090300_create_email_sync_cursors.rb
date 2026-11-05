class CreateEmailSyncCursors < ActiveRecord::Migration[8.1]
  def change
    create_table :email_sync_cursors do |t|
      t.string :provider, null: false
      t.string :account, null: false
      t.string :mailbox, null: false, default: "INBOX"
      t.string :history_id
      t.bigint :uid_validity
      t.bigint :last_uid
      t.datetime :last_synced_at
      t.datetime :last_rescan_at
      t.json :failed_attempts, null: false, default: {} # provider_message_id => failed attempts since the cursor last moved
      t.timestamps
    end
    add_index :email_sync_cursors, %i[provider account mailbox], unique: true
  end
end
